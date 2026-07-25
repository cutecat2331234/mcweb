# frozen_string_literal: true

module Community
  module TopicVisibility
    extend ActiveSupport::Concern

    private

    def topic_visible?(topic, user: current_user)
      Community::ForumAccess.topic_visible?(topic: topic, user: user)
    end

    def ensure_topic_visible!(topic)
      return if topic_visible?(topic)

      raise ActiveRecord::RecordNotFound
    end
  end
end
