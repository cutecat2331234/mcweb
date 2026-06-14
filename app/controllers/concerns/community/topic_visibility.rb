# frozen_string_literal: true

module Community
  module TopicVisibility
    extend ActiveSupport::Concern

    private

    def topic_visible?(topic, user: current_user)
      case topic.status
      when "published"
        true
      when "draft"
        user.present? && topic.user_id == user.id
      when "hidden"
        user.present? && (topic.user_id == user.id || user.permission?("forum.topics.lock"))
      else
        false
      end
    end

    def ensure_topic_visible!(topic)
      return if topic_visible?(topic)

      raise ActiveRecord::RecordNotFound
    end
  end
end
