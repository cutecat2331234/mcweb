# frozen_string_literal: true

module Community
  class CreateUserWarning < ApplicationService
    def initialize(actor:, user:, reason:, points: 1, expire_days: nil)
      @actor = actor
      @user = user
      @reason = reason.to_s.strip
      @points = [ points.to_i, 1 ].max
      @expire_days = expire_days
    end

    def call
      return ServiceResult.failure(error: "warn_user_unauthorized") unless @actor.permission?("forum.users.warn") || @actor.permission?("admin.access")
      return ServiceResult.failure(error: "cannot_warn_self") if @actor.id == @user.id
      return ServiceResult.failure(error: "warning_reason_required") if @reason.blank?

      warning = Community::UserWarning.create!(
        user: @user,
        issuer: @actor,
        reason: @reason,
        points: [ @points, 10 ].min,
        expires_at: warning_expires_at
      )

      Community::NotifyUserWarning.call(warning: warning)
      Community::EnforceWarningThreshold.call(user: @user, actor: @actor)
      ServiceResult.success(warning)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def warning_expires_at
      days = if @expire_days.nil?
               SiteSetting.get("forum.warning_points_expire_days", "90").to_i
      else
               @expire_days.to_i
      end
      return nil if days <= 0

      days.days.from_now
    end
  end
end
