# frozen_string_literal: true

module Community
  class CreateUserWarning < ApplicationService
    def initialize(actor:, user:, reason: nil, points: nil, expire_days: nil, template_id: nil)
      @actor = actor
      @user = user
      template = template_id.present? ? Community::WarningTemplate.find_by(id: template_id) : nil
      @reason = (reason.presence || template&.reason).to_s.strip
      @points = [ (points || template&.points || 1).to_i, 1 ].max
      @expire_days = expire_days.nil? ? template&.expire_days : expire_days
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
      Administration::AuditLogger.call(
        actor: @actor,
        action: "forum.user.warn",
        resource: @user,
        reason: @reason,
        metadata: { points: warning.points, warning_id: warning.id, expires_at: warning.expires_at }.compact
      )
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
