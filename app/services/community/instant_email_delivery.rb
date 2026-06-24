# frozen_string_literal: true

module Community
  class InstantEmailDelivery
    def self.allowed?(user, notification_type:)
      return false if do_not_disturb?(user)
      return false unless NotificationPreference.enabled?(user, channel: "email", notification_type: notification_type)
      return false if defer_to_digest?(user, notification_type: notification_type)

      true
    end

    # While "do not disturb" is active, suppress instant emails (in-app
    # notifications are still recorded; the digest can pick them up later).
    def self.do_not_disturb?(user)
      user.forum_dnd_until.present? && user.forum_dnd_until > Time.current
    end

    def self.defer_to_digest?(user, notification_type:)
      return false unless SendForumDigest::NOTIFICATION_TYPES.include?(notification_type.to_s)

      SendForumDigest::FREQUENCIES.include?(user.forum_digest_frequency.to_s)
    end
  end
end
