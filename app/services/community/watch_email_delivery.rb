# frozen_string_literal: true

module Community
  class WatchEmailDelivery
    MODES = %w[instant digest_only none].freeze

    def self.instant?(user)
      mode = user.forum_watch_email_mode.to_s
      mode.blank? || mode == "instant"
    end

    def self.allowed?(user)
      instant?(user)
    end

    def self.email_allowed?(user, notification_type:)
      allowed?(user) && InstantEmailDelivery.allowed?(user, notification_type: notification_type)
    end
  end
end
