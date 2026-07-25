# frozen_string_literal: true

module Community
  module PollParticipation
    module_function

    def allowed?(user:, poll:)
      return false unless user

      # Re-read the topic before every mutation. A Poll instance can keep its
      # topic association cached across a move/archive/permission change; using
      # that stale object would let a vote bypass the current write boundary.
      topic = poll.topic.reload
      section = topic.section

      return false unless Community::SectionAccess.view?(section: section, user: user)
      return false unless visible?(topic: topic, user: user)
      return false if topic.archived_at.present?
      return false if topic.locked? && !user&.permission?("forum.topics.lock")
      return false unless section.allowed?(user, :reply)
      return false unless section.trust_allowed?(user, :reply)
      return false unless section.writable_by?(user, :reply)
      return false if Community::TopicReplyBan.active.exists?(forum_topic_id: topic.id, user_id: user.id)

      true
    rescue ActiveRecord::RecordNotFound
      false
    end

    def visible?(topic:, user:)
      case topic.status
      when "published"
        true
      when "draft"
        user.present? && user.id == topic.user_id
      when "hidden"
        return false unless user.present?

        user.id == topic.user_id ||
          user.permission?("forum.topics.lock") ||
          Community::SectionModeration.can_moderate_topic?(user: user, topic: topic)
      else
        false
      end
    end
  end
end
