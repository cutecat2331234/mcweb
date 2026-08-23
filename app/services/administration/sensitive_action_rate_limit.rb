# frozen_string_literal: true

require "digest"

module Administration
  # Cross-process atomic reservation for destructive credential checks. Every
  # verifier first reserves both account and request-IP dimensions under stable
  # database row locks. Pending reservations count until their short TTL;
  # failures become fixed-window history and success settles only that attempt.
  class SensitiveActionRateLimit < ApplicationService
    ACTIONS = %i[reserve failure success].freeze
    DEFAULT_LIMIT = 5
    DEFAULT_WINDOW = 15.minutes
    DEFAULT_RESERVATION_TTL = 2.minutes

    def initialize(
      scope:,
      user:,
      action:,
      ip_address: nil,
      context: nil,
      reservation_id: nil,
      limit: DEFAULT_LIMIT,
      window: DEFAULT_WINDOW,
      reservation_ttl: DEFAULT_RESERVATION_TTL
    )
      @scope = scope.to_s
      @user = user
      @action = action.to_sym
      @ip_address = ip_address.to_s.strip.presence || "unknown"
      @context = context.to_s
      @reservation_id = reservation_id.to_s
      @limit = Integer(limit)
      @window = window
      @reservation_ttl = reservation_ttl
    end

    def call
      validate_contract!
      @action == :reserve ? reserve! : settle!
    end

    private

    def validate_contract!
      raise ArgumentError, "unknown sensitive-action rate-limit action" unless ACTIONS.include?(@action)
      raise ArgumentError, "sensitive-action scope is required" if @scope.blank?
      raise ArgumentError, "sensitive-action user is required" unless @user&.id
      raise ArgumentError, "sensitive-action limit must be positive" unless @limit.positive?
      raise ArgumentError, "sensitive-action window must be positive" unless @window.to_i.positive?
      if @action == :reserve
        raise ArgumentError, "sensitive-action reservation TTL must be positive" unless @reservation_ttl.to_i.positive?
        raise ArgumentError, "sensitive-action context is required" if @context.blank?
      elsif @reservation_id.blank?
        raise ArgumentError, "sensitive-action reservation is required"
      end
    end

    def reserve!
      retry_record_not_unique do
        RateLimitCounter.transaction do
          now = Time.current
          counters = locked_counters(counter_keys.values, window: @window, now: now)
          pending = pending_counts(now)
          blocked = counters.select do |counter|
            counter.count + pending.fetch(counter.key, 0) >= @limit
          end
          unless blocked.empty?
            blocked.each do |counter|
              counter.blocked_count += 1
              counter.last_blocked_at = now
              counter.save!
            end
            next ServiceResult.failure(
              error: :sensitive_action_rate_limited,
              code: :rate_limited,
              retry_after: blocked.map { |counter| retry_after(counter, pending, now) }.max
            )
          end

          reservation = Administration::SensitiveActionRateLimitReservation.create!(
            scope: @scope,
            user: @user,
            user_counter_key: counter_keys.fetch(:user),
            ip_counter_key: counter_keys.fetch(:ip),
            context_digest: Digest::SHA256.hexdigest(@context),
            status: "pending",
            limit: @limit,
            window_seconds: @window.to_i,
            expires_at: now + [ @reservation_ttl, @window ].min
          )
          ServiceResult.success(
            reservation_id: reservation.public_id,
            expires_at: reservation.expires_at,
            remaining: counters.map do |counter|
              [ @limit - counter.count - pending.fetch(counter.key, 0) - 1, 0 ].max
            end.min
          )
        end
      end
    end

    def settle!
      reservation = Administration::SensitiveActionRateLimitReservation.find_by(public_id: @reservation_id)
      return failure(:sensitive_action_reservation_invalid) unless reservation
      return failure(:sensitive_action_reservation_invalid) unless
        reservation.scope == @scope && reservation.user_id == @user.id

      desired_status = @action == :failure ? "failed" : "succeeded"
      retry_record_not_unique do
        RateLimitCounter.transaction do
          now = Time.current
          keys = [ reservation.user_counter_key, reservation.ip_counter_key ].sort
          counters = locked_counters(keys, window: reservation.window_seconds.seconds, now: now)
          reservation.lock!
          if reservation.status == desired_status
            next ServiceResult.success(reservation_id: reservation.public_id, idempotent: true)
          end
          unless reservation.status_pending?
            next failure(:sensitive_action_reservation_settlement_conflict)
          end
          if desired_status == "succeeded" && reservation.expires_at <= now
            next failure(:sensitive_action_reservation_expired)
          end

          if desired_status == "failed"
            counters.each do |counter|
              counter.count += 1
              counter.expires_at = counter.window_start + reservation.window_seconds.seconds
              if counter.count >= reservation.limit
                counter.blocked_count += 1
                counter.last_blocked_at = now
              end
              counter.save!
            end
          end
          reservation.update!(status: desired_status, settled_at: now)
          ServiceResult.success(
            reservation_id: reservation.public_id,
            idempotent: false,
            locked: counters.any? { |counter| counter.count >= reservation.limit }
          )
        end
      end
    end

    def locked_counters(keys, window:, now:)
      keys.sort.each do |key|
        RateLimitCounter.find_or_create_by!(key: key) do |counter|
          counter.count = 0
          counter.blocked_count = 0
          counter.window_start = now
          counter.expires_at = now + window
        end
      end
      RateLimitCounter.where(key: keys).order(:key).lock.to_a.tap do |counters|
        counters.each { |counter| reset_if_expired!(counter, window, now) }
      end
    end

    def reset_if_expired!(counter, window, now)
      return unless counter.window_start.blank? || counter.window_start <= now - window

      counter.update!(
        count: 0,
        blocked_count: 0,
        last_blocked_at: nil,
        window_start: now,
        expires_at: now + window
      )
    end

    def pending_counts(now)
      active = Administration::SensitiveActionRateLimitReservation.active_at(now).where(scope: @scope)
      {
        counter_keys.fetch(:user) => active.where(user_counter_key: counter_keys.fetch(:user)).count,
        counter_keys.fetch(:ip) => active.where(ip_counter_key: counter_keys.fetch(:ip)).count
      }
    end

    def retry_after(counter, pending, now)
      candidates = []
      candidates << counter.window_start + @window if counter.count.positive?
      pending_needed = counter.count + pending.fetch(counter.key, 0) - @limit + 1
      if pending_needed.positive?
        column = counter.key == counter_keys.fetch(:user) ? :user_counter_key : :ip_counter_key
        expiry = Administration::SensitiveActionRateLimitReservation.active_at(now)
          .where({ scope: @scope, column => counter.key })
          .order(:expires_at)
          .offset(pending_needed - 1)
          .pick(:expires_at)
        candidates << expiry if expiry
      end
      [ ((candidates.compact.min || now + @window) - now).ceil, 1 ].max
    end

    def counter_keys
      @counter_keys ||= {
        user: "sensitive:#{@scope}:user:#{Digest::SHA256.hexdigest(@user.id.to_s)}",
        ip: "sensitive:#{@scope}:ip:#{Digest::SHA256.hexdigest(@ip_address)}"
      }.freeze
    end

    def retry_record_not_unique
      attempts = 0
      begin
        yield
      rescue ActiveRecord::RecordNotUnique
        attempts += 1
        retry if attempts < 3
        raise
      end
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
