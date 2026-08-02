# frozen_string_literal: true

module Community
  # XenForo-style "Copy thread": duplicate a topic (and its published posts) into
  # another section. Posts are copied without parent/quote links (those reference
  # the source topic) and without firing publish side effects (no re-notifying).
  class CopyTopic < ApplicationService
    def initialize(user:, topic:, section:)
      @user = user
      @topic = topic
      @section = section
    end

    def call
      new_topic = nil
      section_lock_attempts = 0
      begin
        Community::Topic.transaction do
          @topic, _source_section, @section = Community::SectionHierarchyLock.lock_topic!(
            @topic,
            @section
          )
          unless @section.publicly_active?
            return ServiceResult.failure(error: :destination_section_not_available)
          end

          unless Community::SectionModeration.can_move_topic?(user: @user, topic: @topic, to_section: @section)
            return ServiceResult.failure(error: :you_are_not_authorized_to_copy_this_topic)
          end

          new_topic = duplicate_topic
          duplicate_tags(new_topic)
          duplicate_posts(new_topic)
          duplicate_topic_fields(new_topic)
        end
      rescue Community::SectionHierarchyLock::TopicSectionChanged,
        Community::SectionHierarchyLock::HierarchyChanged,
        ActiveRecord::Deadlocked
        section_lock_attempts += 1
        fresh_topic = Community::Topic.with_discarded.find_by(id: @topic.id)
        fresh_section = Community::Section.find_by(id: @section.id)
        if section_lock_attempts <= 2 && fresh_topic && fresh_section
          @topic = fresh_topic
          @section = fresh_section
          retry
        end
        return ServiceResult.failure(error: :topic_not_available)
      end

      Administration::AuditLogger.call(
        actor: @user,
        action: "forum.topic.copy",
        resource: new_topic,
        metadata: { source_topic: @topic.public_id, to_section: @section.slug }
      )
      ServiceResult.success(new_topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def duplicate_topic
      Community::Topic.create!(
        public_id: "topic_#{SecureRandom.alphanumeric(16)}",
        section: @section,
        user: @topic.user,
        title: @topic.title,
        prefix: @topic.prefix,
        status: "published",
        wiki: @topic.wiki,
        last_posted_at: @topic.last_posted_at || Time.current,
        last_post_user: @topic.last_post_user || @topic.user,
        replies_count: @topic.replies_count
      )
    end

    def duplicate_tags(new_topic)
      @topic.topic_tags.pluck(:forum_tag_id).each do |tag_id|
        Community::TopicTag.create!(forum_topic_id: new_topic.id, forum_tag_id: tag_id)
      end
    end

    def duplicate_posts(new_topic)
      @topic.posts.where(status: :published).order(:floor_number).each do |post|
        Community::Post.create!(
          topic: new_topic,
          user: post.user,
          floor_number: post.floor_number,
          body: post.body,
          status: "published",
          post_type: post.post_type,
          created_at: post.created_at
        )
      end
    end

    def duplicate_topic_fields(new_topic)
      field_keys = []
      @topic.topic_field_values.includes(:definition).find_each do |field_value|
        Community::TopicFieldValue.create!(
          topic: new_topic,
          definition: field_value.definition,
          value: field_value.value
        )
        field_keys << field_value.definition.key
      end
      return if field_keys.empty?

      ActiveRecord.after_all_transactions_commit do
        Mcweb::Events.publish(
          "forum.topic.fields.updated",
          topic: new_topic,
          field_keys: field_keys.freeze
        )
      end
    end
  end
end
