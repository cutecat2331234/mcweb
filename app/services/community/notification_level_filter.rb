# frozen_string_literal: true

module Community
  class NotificationLevelFilter
    def self.deliver_in_app?(level:, user:, topic: nil, post: nil, context: :topic_reply)
      case level.to_s
      when "watching", "tracking"
        true
      when "normal"
        case context
        when :topic_reply
          topic.present? && post.present? && (
            TopicParticipant.participated?(user: user, topic: topic) ||
            TopicParticipant.mentioned_in_post?(user: user, post: post)
          )
        else
          false
        end
      else
        false
      end
    end

    def self.deliver_watch_email?(level:, user:, notification_type:)
      return false unless level.to_s == "watching"

      WatchEmailDelivery.email_allowed?(user, notification_type: notification_type)
    end
  end
end
