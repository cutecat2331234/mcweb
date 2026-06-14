# frozen_string_literal: true

module Community
  class EnforceWarningThreshold < ApplicationService
    def initialize(user:, actor: nil)
      @user = user
      @actor = actor
    end

    def call
      threshold = SiteSetting.get("forum.warning_mute_threshold", "").to_i
      return ServiceResult.success(skipped: true) if threshold <= 0

      total = Community::UserWarning.total_points_for(@user)
      return ServiceResult.success(skipped: true) if total < threshold
      return ServiceResult.success(skipped: true) if Community::Mute.muted?(@user)
      return ServiceResult.failure(error: "无法执行自动禁言。") unless @actor

      expires_at = SiteSetting.get("forum.warning_mute_days", "7").to_i
      expires_at = expires_at.positive? ? expires_at.days.from_now : nil

      Community::Mute.create!(
        user: @user,
        reason: "警告积分达到 #{total} 点（阈值 #{threshold}）",
        expires_at: expires_at,
        created_by: @actor
      )

      ServiceResult.success(muted: true)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
