# frozen_string_literal: true

module Community
  class MigrateArchivedSectionTopics < ApplicationService
    class AuditFailure < StandardError; end

    def initialize(source_section:, target_section:, actor:, reason:, ip_address: nil, user_agent: nil, request_id: nil)
      @source_section = source_section
      @target_section = target_section
      @actor = actor
      @reason = reason.to_s.strip
      @ip_address = ip_address
      @user_agent = user_agent
      @request_id = request_id
    end

    def call
      unless @actor&.permission?("forum.topics.move") && @actor.permission?("forum.sections.lifecycle")
        return failure(:permission_denied)
      end
      return failure(:reason_required) if @reason.blank?
      return failure(:reason_too_long) if @reason.length > 1_000
      return failure(:same_section) if @source_section.id == @target_section.id

      moved_topics = []
      source_by_topic_id = {}
      lock_attempts = 0

      begin
        Community::Section.transaction do
          moved_topics = []
          source_by_topic_id = {}
          section_ids, source_sections = lock_source_subtree!
          return failure(:source_must_be_archived) if @source_section.publicly_active?
          return failure(:target_not_available) unless @target_section.publicly_active?

          moved_topics = Community::Topic.where(forum_section_id: section_ids).order(:id).lock.to_a

          moved_topics.each do |topic|
            source_by_topic_id[topic.id] = source_sections.fetch(topic.forum_section_id)
            topic.update!(section: @target_section)
          end

          audit_result = Administration::AuditLogger.call(
            actor: @actor,
            action: "admin.forum_section_topics_migrated",
            resource: @source_section,
            metadata: {
              source_section_id: @source_section.id,
              source_section_slug: @source_section.slug,
              target_section_id: @target_section.id,
              target_section_slug: @target_section.slug,
              subtree_section_ids: section_ids,
              topic_count: moved_topics.length
            },
            before_state: { topic_count: moved_topics.length },
            after_state: { topic_count: 0, target_section_id: @target_section.id },
            reason: @reason,
            ip_address: @ip_address,
            user_agent: @user_agent,
            request_id: @request_id
          )
          raise AuditFailure if audit_result.failure?
        end
      rescue Community::SectionHierarchyLock::HierarchyChanged, ActiveRecord::Deadlocked
        lock_attempts += 1
        fresh_source = Community::Section.find_by(id: @source_section.id)
        fresh_target = Community::Section.find_by(id: @target_section.id)
        unless fresh_source && fresh_target
          return section_not_available_failure
        end
        if lock_attempts <= 2
          @source_section = fresh_source
          @target_section = fresh_target
          retry
        end
        return section_not_available_failure
      rescue ActiveRecord::RecordNotFound
        return section_not_available_failure
      end

      dispatch_webhooks(moved_topics, source_by_topic_id)
      ServiceResult.success(moved_topics:, target_section: @target_section)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    rescue AuditFailure
      failure(:audit_failed)
    end

    private

    # Discover the full source subtree, then lock every involved section in the
    # deterministic order owned by SectionHierarchyLock. Recomputing membership
    # after the locks closes the window where a child can be reparented between
    # discovery and the subsequent topic-row locks.
    def lock_source_subtree!
      discovered_ids = subtree_ids(@source_section).sort
      discovered_sections = Community::Section.where(id: discovered_ids).order(:id).to_a
      unless discovered_sections.map(&:id) == discovered_ids
        raise Community::SectionHierarchyLock::HierarchyChanged
      end

      locked_sections = Community::SectionHierarchyLock.lock!(
        @source_section,
        @target_section,
        *discovered_sections
      )
      @source_section = locked_sections.first
      @target_section = locked_sections.second

      locked_subtree_ids = subtree_ids(@source_section).sort
      unless locked_subtree_ids == discovered_ids
        raise Community::SectionHierarchyLock::HierarchyChanged
      end

      locked_by_id = locked_sections.index_by(&:id)
      source_sections = locked_subtree_ids.to_h do |section_id|
        [ section_id, locked_by_id.fetch(section_id) ]
      end
      [ locked_subtree_ids, source_sections ]
    end

    def subtree_ids(section)
      found = []
      pending = [ section.id ]

      while pending.any?
        batch = pending - found
        break if batch.empty?

        found.concat(batch)
        pending = Community::Section.where(parent_id: batch).pluck(:id)
      end

      found
    end

    def dispatch_webhooks(topics, source_by_topic_id)
      topics.each do |topic|
        source = source_by_topic_id.fetch(topic.id)
        Community::DispatchForumEventWebhook.call(
          event_type: "topic.moved",
          topic: topic,
          extra: {
            from_section: { slug: source.slug, name: source.name },
            to_section: { slug: @target_section.slug, name: @target_section.name }
          }
        )
      rescue StandardError => e
        Rails.logger.error(
          "[ForumSectionMigration] webhook failed topic=#{topic.id}: #{e.class}: #{e.message}"
        )
      end
    end

    def failure(key)
      ServiceResult.failure(
        error: I18n.t("mcweb.services.community.section_topic_migration.#{key}")
      )
    end

    def section_not_available_failure
      ServiceResult.failure(error: I18n.t("mcweb.services.errors.section_not_available"))
    end
  end
end
