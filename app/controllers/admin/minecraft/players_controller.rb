# frozen_string_literal: true

module Admin
  module Minecraft
    class PlayersController < BaseController
      before_action :require_players_page_access, only: :index
      before_action -> { require_permission("minecraft.servers.control") }, only: :kick

      def index
        result = if current_user.permission?("minecraft.players.view")
                   ::Minecraft::AggregatePlayerStatus.call(scope: :active)
        else
                   ServiceResult.success({ players: [] })
        end

        render inertia: "Admin/Minecraft/Players/Index", props: {
          title: t("mcweb.admin.minecraft.players"),
          players: result.success? ? result.value[:players] : [],
          kickUrl: kick_admin_minecraft_players_path,
          backUrl: admin_minecraft_servers_path,
          primaryAccountPermissions: {
            review: current_user.permission?("minecraft.primary_accounts.review"),
            switchForUser: current_user.permission?("minecraft.primary_accounts.switch_for_user")
          },
          primaryAccountRequests: primary_account_requests,
          boundAccounts: bound_accounts
        }
      end

      private

      def require_players_page_access
        return if %w[
          minecraft.players.view
          minecraft.primary_accounts.review
          minecraft.primary_accounts.switch_for_user
        ].any? { |permission| current_user.permission?(permission) }

        redirect_to admin_root_path, alert: t("mcweb.flash.permission_denied")
      end

      def primary_account_requests
        return [] unless current_user.permission?("minecraft.primary_accounts.review")

        ::Minecraft::PrimaryAccountChangeRequest
          .includes(
            :user,
            source_identity_link: { player_profile: :player_identities },
            target_identity_link: { player_profile: :player_identities }
          )
          .recent_first
          .limit(100)
          .map do |request_record|
            {
              id: request_record.id,
              member: {
                id: request_record.user.public_id,
                username: request_record.user.display_name
              },
              sourceAccount: account_summary(request_record.source_identity_link),
              targetAccount: account_summary(request_record.target_identity_link),
              status: request_record.status,
              reason: request_record.request_reason,
              decisionReason: request_record.decision_reason,
              requestedAt: request_record.requested_at.iso8601,
              expiresAt: request_record.expires_at.iso8601,
              resolvedAt: request_record.resolved_at&.iso8601,
              lockVersion: request_record.lock_version,
              decisionUrl: admin_minecraft_primary_account_change_request_path(request_record)
            }
          end
      end

      def bound_accounts
        return [] unless current_user.permission?("minecraft.primary_accounts.switch_for_user")

        links = ::Minecraft::IdentityLink.active
                                       .includes(:user, player_profile: { player_identities: :skin_avatar_file_attachment })
                                       .order(:user_id, :linked_at, :id)
                                       .limit(500)
        links.filter_map do |link|
          identity = link.player_profile.active_identity
          next unless identity

          {
            linkId: link.id,
            member: {
              id: link.user.public_id,
              username: link.user.display_name
            },
            username: identity.username,
            uuid: identity.external_uuid,
            identityType: identity.identity_type,
            primary: link.primary_account?,
            avatarUrl: cached_avatar_url(identity),
            switchUrl: admin_minecraft_primary_account_path(user_id: link.user_id)
          }
        end
      end

      def account_summary(link)
        identity = link&.player_profile&.active_identity
        return nil unless link && identity

        {
          linkId: link.id,
          username: identity.username,
          uuid: identity.external_uuid,
          active: link.unlinked_at.nil?,
          primary: link.primary_account?,
          avatarUrl: cached_avatar_url(identity)
        }
      end

      def cached_avatar_url(identity)
        return "/minecraft/default-skin-avatar.svg" unless identity.skin_avatar_file.attached?

        minecraft_cached_skin_path(identity, variant: "avatar")
      end

      public

      def kick
        server = ::Minecraft::Server.find_by!(public_id: params[:server_id])
        uuid = params[:uuid].to_s.strip
        username = params[:username].to_s.strip

        command = if uuid.present?
                    "minecraft:kick #{uuid}"
        elsif username.present?
                    "kick #{username}"
        end

        if command.blank?
          redirect_to admin_minecraft_players_path, alert: t("mcweb.flash.player_kick_target_required")
          return
        end

        result = ::Minecraft::EnqueueConsoleCommand.call(server: server, command: command, delivery_prefix: "kick-#{SecureRandom.uuid}")
        if result.success?
          ::Minecraft::RecordServerAudit.call(
            action: "minecraft.player.kick",
            actor: current_user,
            server: server,
            metadata: { uuid: uuid.presence, username: username.presence },
            request: request
          )
          redirect_to admin_minecraft_players_path, notice: t("mcweb.flash.player_kick_queued")
        else
          redirect_to admin_minecraft_players_path, alert: service_error_message(result)
        end
      end
    end
  end
end
