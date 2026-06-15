# frozen_string_literal: true

module Community
  module PollParticipation
    module_function

    def allowed?(user:, poll:)
      topic = poll.topic
      section = topic.section

      return false unless topic_visible?(topic, user)
      return false if topic.locked? && !user&.permission?("forum.topics.lock")
      return false unless section.allowed?(user, :reply)
      return false unless section.trust_allowed?(user, :reply)
      return false unless section.writable_by?(user, :reply)
      return false if Community::TopicReplyBan.active.exists?(forum_topic_id: topic.id, user_id: user.id)

      true
    end

    def topic_visible?(topic, user)
      case topic.status
      when "published"
        true
      when "draft"
        user&.id == topic.user_id
      when "hidden"
        user&.permission?("forum.topics.lock")
      else
        false
      end
    end
    private_class_method :topic_visible?
  end
end
