# frozen_string_literal: true

module Administration
  class RateLimiter < ApplicationService
    def initialize(key:, limit:, window:, developer_mode_bypass: true)
      @key = key.to_s
      @limit = limit
      @window = window
      @developer_mode_bypass = developer_mode_bypass
    end

    def call
      if @developer_mode_bypass &&
          Mcweb::DeveloperMode.allow?(:skip_rate_limits)
        return ServiceResult.success(remaining: nil, developer_mode_bypassed: true)
      end

      attempts = 0
      begin
        RateLimitCounter.transaction do
          counter = RateLimitCounter.lock.find_or_initialize_by(key: @key)
          now = Time.current
          reset_counter_if_expired!(counter, now)
          counter.expires_at = counter.window_start + @window

          if counter.count >= @limit
            counter.blocked_count += 1
            counter.last_blocked_at = now
            counter.save!

            return ServiceResult.failure(
              error: I18n.t("mcweb.flash.rate_limited", default: "Rate limit exceeded."),
              code: :rate_limited,
              retry_after: retry_after(counter, now)
            )
          end

          counter.count += 1
          counter.save!

          ServiceResult.success(remaining: @limit - counter.count)
        end
      rescue ActiveRecord::RecordNotUnique
        # Two concurrent first-hits for a brand-new key raced to insert. Retry: the row
        # now exists, so the locked find_or_initialize_by becomes a normal update.
        attempts += 1
        retry if attempts < 3
        raise
      end
    end

    private

    def reset_counter_if_expired!(counter, now)
      if counter.new_record? || counter.window_start.blank? || counter.window_start <= now - @window
        counter.count = 0
        counter.blocked_count = 0
        counter.last_blocked_at = nil
        counter.window_start = now
      end
    end

    def retry_after(counter, now)
      [ (counter.window_start + @window - now).ceil, 1 ].max
    end
  end
end
