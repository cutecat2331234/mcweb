# frozen_string_literal: true

module Admin
  module Minecraft
    class PlayersController < BaseController
      before_action -> { require_permission("minecraft.players.view") }
      before_action -> { require_permission("minecraft.servers.control") }, only: :kick

      def index
        result = Minecraft::AggregatePlayerStatus.call(scope: :active)

        render inertia: "Admin/Minecraft/Players/Index", props: {
          title: t("mcweb.admin.minecraft.players"),
          players: result.success? ? result.value[:players] : [],
          kickUrl: kick_admin_minecraft_players_path,
          backUrl: admin_minecraft_servers_path
        }
      end

      def kick
        server = Minecraft::Server.find_by!(public_id: params[:server_id])
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

        result = Minecraft::EnqueueConsoleCommand.call(server: server, command: command, delivery_prefix: "kick-#{SecureRandom.uuid}")
        if result.success?
          Minecraft::RecordServerAudit.call(
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
