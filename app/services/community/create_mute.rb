# frozen_string_literal: true

module Community
  class CreateMute < ApplicationService
    def initialize(actor:, user:, section: nil, reason: nil, expires_at: nil)
      @actor = actor
      @user = user
      @section = section
      @reason = reason
      @expires_at = expires_at
    end

    def call
      unless @actor.permission?("forum.users.mute")
        return ServiceResult.failure(error: "Not authorized to mute users.")
      end

      mute = Community::Mute.create!(
        user: @user,
        section: @section,
        reason: @reason,
        expires_at: @expires_at,
        created_by: @actor
      )

      Administration::AuditLogger.call(
        actor: @actor,
        action: "forum.user.silence",
        resource: @user,
        reason: @reason,
        metadata: { section: @section&.slug, mute_id: mute.id, expires_at: @expires_at }.compact
      )
      notify_muted!(mute)
      ServiceResult.success(mute)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def notify_muted!(mute)
      return unless NotificationPreference.enabled?(@user, channel: "in_app", notification_type: "forum.silenced")

      scope = mute.section&.name || I18n.t("mcweb.forum.mute.site_wide", default: "全站")
      Community::InAppNotification.notify(
        user: @user,
        notification_type: "forum.silenced",
        key: "silenced",
        area: scope,
        reason: @reason.presence || "—",
        metadata: { mute_id: mute.id }
      )
    end
  end
end
