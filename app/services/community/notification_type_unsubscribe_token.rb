# frozen_string_literal: true

module Community
  class NotificationTypeUnsubscribeToken
    InvalidToken = Class.new(StandardError)
    PURPOSE = "notification_type_unsubscribe"

    def self.generate(user, notification_type:)
      Rails.application.message_verifier(PURPOSE).generate(
        { "user_id" => user.id, "notification_type" => notification_type.to_s },
        expires_in: 30.days
      )
    end

    def self.verify(token)
      payload = Rails.application.message_verifier(PURPOSE).verify(token)
      user_id = payload["user_id"] || payload[:user_id]
      notification_type = payload["notification_type"] || payload[:notification_type]
      raise InvalidToken if user_id.blank? || notification_type.blank?

      [ user_id, notification_type ]
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      raise InvalidToken
    end
  end
end
