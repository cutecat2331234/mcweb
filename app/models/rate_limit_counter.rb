class RateLimitCounter < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  validates :count, numericality: { greater_than_or_equal_to: 0 }
  validates :window_start, presence: true

  def self.increment!(key, limit:, window:)
    counter = find_or_initialize_by(key: key)
    reset_window!(counter, window) if counter.window_expired?(window)

    counter.count += 1
    counter.window_start ||= Time.current
    counter.save!

    counter.within_limit?(limit)
  end

  def self.check!(key, limit:, window:)
    counter = find_by(key: key)
    return true unless counter

    reset_window!(counter, window) if counter.window_expired?(window)
    counter.within_limit?(limit)
  end

  def self.reset!(key)
    find_by(key: key)&.destroy
  end

  def within_limit?(limit)
    count <= limit
  end

  def window_expired?(window)
    window_start.nil? || window_start < window.ago
  end

  def self.reset_window!(counter, window)
    counter.count = 0
    counter.window_start = Time.current
  end
  private_class_method :reset_window!
end
