# frozen_string_literal: true

module Community
  class MergeTopics < ApplicationService
    def initialize(user:, source:, target_public_id:)
      @user = user
      @source = source
      @target_public_id = target_public_id.to_s.strip
    end

    def call
      unless @user.permission?("forum.topics.move") || @user.permission?("forum.topics.lock")
        return ServiceResult.failure(error: :you_are_not_authorized_to_merge_topics)
      end

      target = Community::Topic.find_by(public_id: @target_public_id, status: :published)
      return ServiceResult.failure(error: :target_topic_not_found) unless target
      return ServiceResult.failure(error: :cannot_merge_a_topic_into_itself) if @source.id == target.id

      lock_attempts = 0
      begin
        Community::Topic.transaction do
          @source, target = Community::SectionHierarchyLock.lock_topics!(@source, target)
          return ServiceResult.failure(error: :target_topic_not_found) unless target.status == "published"
          unless target.section.publicly_active?
            return ServiceResult.failure(error: :destination_section_not_available)
          end

          posts_to_move = Community::Post.with_discarded
            .where(forum_topic_id: @source.id)
            .where.not(floor_number: 1)
            .order(:floor_number)
            .to_a
          moved_posts_by_id = posts_to_move.index_by(&:id)
          next_floor = target.posts.with_discarded.maximum(:floor_number).to_i

          posts_to_move.each_with_index do |post, index|
            updates = { topic: target, floor_number: next_floor + index + 1 }
            if post.parent_post_id.present? && !moved_posts_by_id.key?(post.parent_post_id)
              updates[:parent_post_id] = nil
            end
            post.update!(updates)
          end

          source_solved_post_id = moved_posts_by_id.key?(@source.solved_post_id) ? nil : @source.solved_post_id
          @source.update!(status: :hidden, locked: true, solved_post_id: source_solved_post_id)
          Community::SyncTopicLastPost.call(topic: @source)
          Community::SyncTopicLastPost.call(topic: target)
        end
      rescue Community::SectionHierarchyLock::TopicSectionChanged,
        Community::SectionHierarchyLock::HierarchyChanged,
        ActiveRecord::Deadlocked
        lock_attempts += 1
        fresh_source = Community::Topic.with_discarded.find_by(id: @source.id)
        fresh_target = Community::Topic.with_discarded.find_by(id: target.id)
        if lock_attempts <= 2 && fresh_source && fresh_target
          @source = fresh_source
          target = fresh_target
          retry
        end
        return ServiceResult.failure(error: :topic_not_available)
      end

      Administration::AuditLogger.call(
        actor: @user,
        action: "forum.topics.merge",
        resource: target,
        metadata: { source_topic: @source.public_id, target_topic: target.public_id }
      )
      ServiceResult.success(target)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
