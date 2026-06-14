class NotificationPreference < ApplicationRecord
  belongs_to :user

  validates :channel, presence: true
  validates :notification_type, presence: true
  validates :user_id, uniqueness: { scope: [ :channel, :notification_type ] }

  scope :enabled, -> { where(enabled: true) }

  def self.enabled?(user, channel:, notification_type:)
    pref = find_by(user: user, channel: channel, notification_type: notification_type)
    pref.nil? || pref.enabled?
  end

  def self.set!(user, channel:, notification_type:, enabled:)
    pref = find_or_initialize_by(user: user, channel: channel, notification_type: notification_type)
    pref.enabled = enabled
    pref.save!
  end
end
