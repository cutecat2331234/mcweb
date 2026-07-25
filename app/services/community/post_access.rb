# frozen_string_literal: true

module Community
  module PostAccess
    module_function

    def readable?(post:, user:)
      Community::ForumAccess.post_visible?(post: post, user: user)
    end

    def editable?(post:, user:)
      return false unless post
      return false unless user
      return false if post.deleted_at.present?
      return false if post.status == "deleted"

      topic = post.topic
      return false if topic.archived_at.present?
      return false unless topic_readable?(topic: topic, user: user)
      return false unless PollParticipation.visible?(topic: topic, user: user)
      return false if post.whisper? && !whisper_visible?(post: post, user: user)
      return true if user&.permission?("forum.topics.lock")
      return true if Community::SectionModeration.can_moderate_topic?(user: user, topic: topic)
      return true if post.status == "published"
      return true if post.status == "hidden" && user&.id == post.user_id

      false
    end

    def topic_readable?(topic:, user:)
      Community::ForumAccess.topic_readable?(topic: topic, user: user)
    end

    def whisper_visible?(post:, user:)
      Community::ForumAccess.whisper_visible?(post: post, user: user)
    end
  end
end
