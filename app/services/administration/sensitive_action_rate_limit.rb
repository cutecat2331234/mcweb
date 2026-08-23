# frozen_string_literal: true

require "digest"

module Administration
  # Failure-only, multi-dimensional throttling for destructive step-up checks.
  # Account and request-IP buckets are independent, but are locked and updated
  # together in deterministic key order so one dimension cannot bypass another.
  class SensitiveActionRateLimit < ApplicationService
    ACTIONS = %i[check failure success].freeze
    DEFAULT_LIMIT = 5
    DEFAULT_WINDOW = 15.minutes

    def initialize(scope:, user:, ip_address:, action:, limit: DEFAULT_LIMIT, window: DEFAULT_WINDOW)
      @scope = scope.to_s
      @user = user
      @ip_address = ip_address.to_s.strip.presence || "unknown"
      @action = action.to_sym
      @limit = Integer(limit)
      @window = window
    end

    def call
      raise ArgumentError, "unknown sensitive-action rate-limit action" unless ACTIONS.include?(@action)
      raise ArgumentError, "sensitive-action scope is required" if @scope.blank?
      raise ArgumentError, "sensitive-action user is required" unless @user&.id
      raise ArgumentError, "sensitive-action limit must be positive" unless @limit.positive?

      attempts = 0
      begin
        RateLimitCounter.transaction do
          counters = locked_counters(create: @action == :failure)
          now = Time.current
          counters.each { |counter| reset_if_expired!(counter, now) }

          case @action
          when :check
            check_result(counters, now)
          when :failure
            record_failure(counters, now)
          when :success
            RateLimitCounter.where(key: counter_keys).delete_all
            ServiceResult.success(cleared: true)
          end
        end
      rescue ActiveRecord::RecordNotUnique
        attempts += 1
        retry if attempts < 3
        raise
      end
    end

    private

    def locked_counters(create:)
      if create
        counter_keys.each do |key|
          RateLimitCounter.find_or_create_by!(key: key) do |counter|
            counter.count = 0
            counter.blocked_count = 0
            counter.window_start = Time.current
            counter.expires_at = Time.current + @window
          end
        end
      end
      RateLimitCounter.where(key: counter_keys).order(:key).lock.to_a
    end

    def check_result(counters, now)
      blocked = counters.select { |counter| counter.count >= @limit }
      return ServiceResult.success(remaining: remaining(counters)) if blocked.empty?

      blocked.each do |counter|
        counter.blocked_count += 1
        counter.last_blocked_at = now
        counter.save!
      end
      ServiceResult.failure(
        error: :sensitive_action_rate_limited,
        code: :rate_limited,
        retry_after: blocked.map { |counter| retry_after(counter, now) }.max
      )
    end

    def record_failure(counters, now)
      counters.each do |counter|
        counter.count += 1
        counter.expires_at = counter.window_start + @window
        if counter.count >= @limit
          counter.blocked_count += 1
          counter.last_blocked_at = now
        end
        counter.save!
      end
      ServiceResult.success(
        remaining: remaining(counters),
        locked: counters.any? { |counter| counter.count >= @limit }
      )
    end

    def reset_if_expired!(counter, now)
      return unless counter.window_start.blank? || counter.window_start <= now - @window

      counter.assign_attributes(
        count: 0,
        blocked_count: 0,
        last_blocked_at: nil,
        window_start: now,
        expires_at: now + @window
      )
      counter.save! if counter.persisted?
    end

    def remaining(counters)
      return @limit if counters.empty?

      counters.map { |counter| [ @limit - counter.count, 0 ].max }.min
    end

    def retry_after(counter, now)
      [ (counter.window_start + @window - now).ceil, 1 ].max
    end

    def counter_keys
      @counter_keys ||= {
        "user" => @user.id.to_s,
        "ip" => @ip_address
      }.map do |dimension, identifier|
        digest = Digest::SHA256.hexdigest(identifier)
        "sensitive:#{@scope}:#{dimension}:#{digest}"
      end.sort.freeze
    end
  end
end
