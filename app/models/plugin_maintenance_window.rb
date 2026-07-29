# frozen_string_literal: true

class PluginMaintenanceWindow < ApplicationRecord
  DEFAULT_DURATION = 30.minutes
  CACHE_KEY = "mcweb/plugins/maintenance-active"

  belongs_to :actor, class_name: "User", optional: true

  validates :operation_id,
            presence: true,
            length: { maximum: 191 },
            uniqueness: true
  validates :plugin_id, length: { maximum: 191 }, allow_nil: true
  validates :started_at, :expires_at, presence: true
  validate :expiry_follows_start

  scope :currently_active, lambda {
    where(active: true).where("expires_at > ?", Time.current)
  }

  class << self
    def open!(operation_id:, plugin_id: nil, actor: nil, duration: DEFAULT_DURATION)
      now = Time.current
      create!(
        operation_id:,
        plugin_id: plugin_id.to_s.presence,
        actor:,
        active: true,
        started_at: now,
        expires_at: now + duration
      ).tap { clear_active_cache! }
    end

    def active?
      Rails.cache.fetch(CACHE_KEY, expires_in: 1.second) do
        currently_active.exists?
      end
    rescue ActiveRecord::ActiveRecordError
      false
    end

    def clear_active_cache!
      Rails.cache.delete(CACHE_KEY)
    end
  end

  def close!
    with_lock do
      update!(active: false, ended_at: Time.current) if active?
    end
    self.class.clear_active_cache!
    self
  end

  private

  def expiry_follows_start
    return unless started_at && expires_at
    return if expires_at > started_at

    errors.add(:expires_at, :invalid)
  end
end
