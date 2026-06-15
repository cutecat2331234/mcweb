class Notification < ApplicationRecord
  belongs_to :user

  validates :notification_type, presence: true
  validates :title, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :read, -> { where.not(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  def read?
    read_at.present?
  end

  def mark_read!
    update!(read_at: Time.current) unless read?
  end

  def destination_path
    metadata["path"].presence || metadata[:path].presence ||
      metadata["url"].presence || metadata[:url].presence
  end

  def self.notify!(user:, notification_type:, title:, body: nil, metadata: {})
    create!(
      user: user,
      notification_type: notification_type,
      title: title,
      body: body,
      metadata: metadata
    )
  end
end
