class Notification < ApplicationRecord
  belongs_to :user

  validates :notification_type, presence: true
  validates :title, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :read, -> { where.not(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }
  scope :alerts, -> { where(auto_dismiss: true) }

  # XenForo-style transient "alerts" — low-priority types that can be dismissed
  # in bulk (vs persistent notifications kept until explicitly read).
  ALERT_TYPES = %w[
    forum.reaction
    forum.new_follower
    forum.linked
    forum.post_reply
    forum.quote
    forum.profile_post
    forum.profile_post_comment
  ].freeze

  def read?
    read_at.present?
  end

  def mark_read!
    update!(read_at: Time.current) unless read?
  end

  def destination_path
    raw = metadata["path"].presence || metadata[:path].presence ||
      metadata["url"].presence || metadata[:url].presence
    Mcweb::Paths.normalize(raw)
  end

  def self.notify!(user:, notification_type:, title:, body: nil, metadata: {})
    notification = create!(
      user: user,
      notification_type: notification_type,
      title: title,
      body: body,
      metadata: metadata,
      auto_dismiss: ALERT_TYPES.include?(notification_type.to_s)
    )
    broadcast_new(notification)
    enqueue_web_push(notification)
    notification
  end

  def self.enqueue_web_push(notification)
    Community::DeliverWebPushJob.perform_later(notification.id)
  rescue StandardError
    nil
  end

  # Push a live update to the recipient's notification stream. Never let a
  # broadcast failure (e.g. cable adapter hiccup) block notification creation.
  def self.broadcast_new(notification)
    Community::NotificationsChannel.broadcast_to(
      notification.user,
      {
        id: notification.id,
        title: notification.title,
        body: notification.body,
        type: notification.notification_type,
        path: notification.destination_path,
        unread_count: notification.user.notifications.unread.count
      }
    )
  rescue StandardError
    nil
  end
end
