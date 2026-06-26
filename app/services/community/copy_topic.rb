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
      unless Community::SectionModeration.can_move_topic?(user: @user, topic: @topic, to_section: @section)
        return ServiceResult.failure(error: "You are not authorized to copy this topic.")
      end

      new_topic = nil
      ActiveRecord::Base.transaction do
        new_topic = duplicate_topic
        duplicate_tags(new_topic)
        duplicate_posts(new_topic)
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
      @topic.topic_tags.pluck(:tag_id).each do |tag_id|
        Community::TopicTag.create!(forum_topic_id: new_topic.id, tag_id: tag_id)
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
  end
end
