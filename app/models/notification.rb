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
    create!(
      user: user,
      notification_type: notification_type,
      title: title,
      body: body,
      metadata: metadata,
      auto_dismiss: ALERT_TYPES.include?(notification_type.to_s)
    )
  end
end
