# frozen_string_literal: true

module Community
  module PostAccess
    module_function

    def readable?(post:, user:)
      topic = post.topic
      return false unless topic_readable?(topic: topic, user: user)
      return false unless PollParticipation.visible?(topic: topic, user: user)
      return false if post.whisper? && !whisper_visible?(post: post, user: user)
      return true if user&.permission?("forum.topics.lock")
      return true if post.status == "published"

      if post.status == "pending_approval"
        return true if user&.id == post.user_id
        return true if Community::SectionModeration.can_moderate_topic?(user: user, topic: topic)
      end

      false
    end

    def editable?(post:, user:)
      topic = post.topic
      return false unless topic_readable?(topic: topic, user: user)
      return false unless PollParticipation.visible?(topic: topic, user: user)
      return false if post.whisper? && !whisper_visible?(post: post, user: user)
      return true if user&.permission?("forum.topics.lock")
      return true if post.status == "published"
      return true if post.status == "hidden" && user&.id == post.user_id

      false
    end

    def topic_readable?(topic:, user:)
      return false if topic.unlisted? && !(user&.permission?("forum.topics.lock") || user&.id == topic.user_id)
      return false unless Community::Topic.accessible_by(user).where(id: topic.id).exists?

      true
    end

    def whisper_visible?(post:, user:)
      return true if user&.permission?("forum.topics.lock")
      return true if Community::SectionModeration.can_moderate_topic?(user: user, topic: post.topic)

      false
    end
  end
end
