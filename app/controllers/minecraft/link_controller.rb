# frozen_string_literal: true

module Minecraft
  class LinkController < ApplicationController
    include PrivateNoStoreResponse

    before_action :require_login
    before_action :rate_limit_link_attempts!, only: :create

    def show
      Minecraft::ExpirePrimaryAccountChangeRequests.call(user: current_user)
      render inertia: "Minecraft/Link/Show", props: link_page_props
    end

    def create
      result = Minecraft::CompleteLink.call(
        user: current_user,
        code: link_params[:code]
      )

      if result.success?
        redirect_to minecraft_link_path, notice: t("mcweb.flash.minecraft_linked")
      else
        render inertia: "Minecraft/Link/Show",
               status: :unprocessable_entity,
               props: link_page_props.merge(form_error: service_error_message(result))
      end
    end

    private

    def link_params
      params.require(:link).permit(:code)
    end

    def rate_limit_link_attempts!
      result = Administration::RateLimiter.call(
        key: "minecraft_link:#{current_user.id}:#{request.remote_ip}",
        limit: 10,
        window: 15.minutes
      )
      return unless result.failure?

      render inertia: "Minecraft/Link/Show",
             status: :too_many_requests,
             props: link_page_props.merge(
               form_error: t("mcweb.flash.rate_limited", default: "操作过于频繁，请稍后再试。")
             )
    end

    def link_page_props
      policy = Minecraft::PrimaryAccountPolicy.snapshot(user: current_user)
      links = Minecraft::IdentityLink.active
                                     .where(user: current_user)
                                     .includes(player_profile: { player_identities: [
                                       :skin_avatar_file_attachment,
                                       :skin_texture_file_attachment
                                     ] })
                                     .order(primary_account: :desc, linked_at: :asc, id: :asc)
      accounts = links.filter_map do |link|
        identity = link.player_profile.active_identity
        next unless identity

        {
          id: link.id,
          playerId: link.player_profile.public_id,
          username: identity.username,
          uuid: identity.external_uuid,
          identityType: identity.identity_type,
          primary: link.primary_account?,
          linkedAt: link.linked_at&.iso8601,
          skinCached: identity.skin_cached?,
          skinCachedAt: identity.skin_cached_at&.iso8601,
          avatarUrl: cached_avatar_url(identity),
          setPrimaryUrl: minecraft_primary_account_path(link),
          unlinkUrl: minecraft_identity_link_path(link),
          unlinkConfirmation: identity.username,
          lockVersion: link.lock_version
        }
      end
      pending = Minecraft::PrimaryAccountChangeRequest.pending
                                                       .includes(target_identity_link: :player_profile)
                                                       .find_by(user: current_user)

      {
        accounts: accounts,
        primaryPolicy: {
          switchPolicy: policy.switch_policy,
          cooldownSeconds: policy.cooldown_seconds,
          cooldownRemainingSeconds: policy.cooldown_remaining_seconds,
          nextAllowedAt: policy.next_allowed_at&.iso8601,
          requestExpiryHours: policy.request_expiry_hours
        },
        pendingRequest: pending && {
          id: pending.id,
          status: pending.status,
          targetAccount: pending.target_identity_link.player_profile.active_identity&.username,
          reason: pending.request_reason,
          requestedAt: pending.requested_at.iso8601,
          expiresAt: pending.expires_at.iso8601,
          lockVersion: pending.lock_version,
          cancelUrl: minecraft_primary_account_change_request_path(pending)
        }
      }
    end

    def cached_avatar_url(identity)
      return "/minecraft/default-skin-avatar.png" unless identity.skin_avatar_file.attached?

      minecraft_cached_skin_path(identity, variant: "avatar")
    end
  end
end
