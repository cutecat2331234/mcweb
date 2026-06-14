# frozen_string_literal: true

module Administration
  class RateLimiter < ApplicationService
    def initialize(key:, limit:, window:)
      @key = key.to_s
      @limit = limit
      @window = window
    end

    def call
      RateLimitCounter.transaction do
        counter = RateLimitCounter.lock.find_or_initialize_by(key: @key)
        reset_counter_if_expired!(counter)

        if counter.count >= @limit
          return ServiceResult.failure(error: "Rate limit exceeded.")
        end

        counter.count += 1
        counter.save!

        ServiceResult.success(remaining: @limit - counter.count)
      end
    end

    private

    def reset_counter_if_expired!(counter)
      if counter.new_record? || counter.window_start.blank? || counter.window_start < @window.ago
        counter.count = 0
        counter.window_start = Time.current
      end
    end

    def retry_after(counter)
      (counter.window_start + @window - Time.current).ceil
    end
  end
end
