# frozen_string_literal: true

module Community
  class EnforceWarningThreshold < ApplicationService
    def initialize(user:, actor: nil)
      @user = user
      @actor = actor
    end

    def call
      total = Community::UserWarning.total_points_for(@user)
      maybe_suspend!(total)

      threshold = SiteSetting.get("forum.warning_mute_threshold", "").to_i
      return ServiceResult.success(skipped: true) if threshold <= 0
      return ServiceResult.success(skipped: true) if total < threshold
      return ServiceResult.success(skipped: true) if Community::Mute.muted?(@user)
      return ServiceResult.failure(error: "auto_silence_failed") unless @actor

      expires_at = SiteSetting.get("forum.warning_mute_days", "7").to_i
      expires_at = expires_at.positive? ? expires_at.days.from_now : nil

      Community::Mute.create!(
        user: @user,
        reason: I18n.t("mcweb.forum.enforce_warning.reason", total: total, threshold: threshold),
        expires_at: expires_at,
        created_by: @actor
      )

      ServiceResult.success(muted: true)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    # XenForo-style escalation: suspend (lock out of sign-in) at a higher points
    # threshold than the auto-mute. Off by default (threshold unset).
    def maybe_suspend!(total)
      threshold = SiteSetting.get("forum.warning_suspend_threshold", "").to_i
      return if threshold <= 0 || total < threshold

      days = SiteSetting.get("forum.warning_suspend_days", "7").to_i
      return unless days.positive?
      return if @user.locked_until&.future?

      @user.update!(locked_until: days.days.from_now)
    end
  end
end
