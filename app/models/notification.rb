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
    values = metadata.is_a?(Hash) ? metadata : {}
    raw = values["path"].presence || values[:path].presence ||
      values["url"].presence || values[:url].presence
    Mcweb::Paths.normalize(raw)
  end

  def self.notify!(user:, notification_type:, title:, body: nil, metadata: {})
    transaction do
      notification = create!(
        user: user,
        notification_type: notification_type,
        title: title,
        body: body,
        metadata: metadata,
        auto_dismiss: ALERT_TYPES.include?(notification_type.to_s)
      )
      Operations::DurableEnqueue.record!(
        handler: "community.web_push",
        source_id: notification.id,
        dedupe_key: "notification:#{notification.id}"
      )
      notification
    end
  end

  def self.enqueue_web_push(notification_or_id)
    notification_id = notification_or_id.respond_to?(:id) ? notification_or_id.id : notification_or_id
    Community::DeliverWebPushJob.perform_later(notification_id)
  rescue StandardError
    nil
  end
end
