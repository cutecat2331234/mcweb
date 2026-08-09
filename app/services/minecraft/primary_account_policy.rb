# frozen_string_literal: true

module Minecraft
  class PrimaryAccountPolicy
    POLICIES = %w[immediate staff_approval administrator_only].freeze
    DEFAULT_POLICY = "immediate"
    DEFAULT_COOLDOWN_SECONDS = 0
    DEFAULT_REQUEST_EXPIRY_HOURS = 72
    MAX_COOLDOWN_SECONDS = 31.days.to_i
    MAX_REQUEST_EXPIRY_HOURS = 24 * 30

    Snapshot = Data.define(
      :switch_policy,
      :cooldown_seconds,
      :request_expiry_hours,
      :last_changed_at,
      :next_allowed_at,
      :cooldown_remaining_seconds
    )

    class << self
      def snapshot(user:, at: Time.current)
        policy = normalized_policy
        cooldown = normalized_integer(
          SiteSetting.get("minecraft.primary_account.cooldown_seconds", DEFAULT_COOLDOWN_SECONDS),
          default: DEFAULT_COOLDOWN_SECONDS,
          maximum: MAX_COOLDOWN_SECONDS
        )
        expiry = normalized_integer(
          SiteSetting.get("minecraft.primary_account.request_expiry_hours", DEFAULT_REQUEST_EXPIRY_HOURS),
          default: DEFAULT_REQUEST_EXPIRY_HOURS,
          minimum: 1,
          maximum: MAX_REQUEST_EXPIRY_HOURS
        )
        last_changed_at = Minecraft::PrimaryAccountChangeEvent
          .where(user: user)
          .for_cooldown
          .maximum(:changed_at)
        next_allowed_at = last_changed_at && cooldown.positive? ? last_changed_at + cooldown.seconds : nil
        remaining = next_allowed_at && next_allowed_at > at ? (next_allowed_at - at).ceil : 0

        Snapshot.new(
          switch_policy: policy,
          cooldown_seconds: cooldown,
          request_expiry_hours: expiry,
          last_changed_at: last_changed_at,
          next_allowed_at: next_allowed_at,
          cooldown_remaining_seconds: remaining
        )
      end

      def normalized_policy
        candidate = SiteSetting.get(
          "minecraft.primary_account.switch_policy",
          DEFAULT_POLICY
        ).to_s
        candidate.in?(POLICIES) ? candidate : DEFAULT_POLICY
      end

      private

      def normalized_integer(value, default:, minimum: 0, maximum:)
        integer = Integer(value, exception: false)
        return default unless integer

        integer.clamp(minimum, maximum)
      end
    end
  end
end
