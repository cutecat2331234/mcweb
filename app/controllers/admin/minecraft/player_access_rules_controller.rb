# frozen_string_literal: true

module Admin
  module Minecraft
    class PlayerAccessRulesController < BaseController
      PAGE_SIZE = 50

      before_action -> { require_permission("minecraft.servers.control") }
      before_action :set_rule, only: :destroy

      def index
        scope = ::Minecraft::PlayerAccessRule
          .includes(:server, :created_by, :revoked_by, :apply_task, :revoke_task)
          .recent
        before_id = Integer(params[:before_id], exception: false)
        scope = scope.where("minecraft_player_access_rules.id < ?", before_id) if before_id&.positive?
        records = scope.limit(PAGE_SIZE + 1).to_a
        has_more = records.length > PAGE_SIZE
        records = records.first(PAGE_SIZE)

        render inertia: "Admin/Minecraft/PlayerAccessRules/Index", props: {
          copy: t("mcweb.admin.minecraft.player_access_rules"),
          ruleTypes: ::Minecraft::PlayerAccessRule::RULE_TYPES,
          servers: ::Minecraft::Server.order(:name, :id).map do |server|
            {
              id: server.public_id,
              name: server.name,
              status: server.status,
              connectorReady: connector_ready?(server)
            }
          end,
          rules: records.map { |rule| serialize_rule(rule) },
          paths: {
            create: admin_minecraft_player_access_rules_path,
            players: admin_minecraft_players_path,
            next: has_more ? admin_minecraft_player_access_rules_path(before_id: records.last.id) : nil
          }
        }
      end

      def create
        attributes = params.require(:access_rule).permit(
          :server_id, :rule_type, :username, :player_uuid, :reason, :expires_at, :idempotency_key
        )
        server = ::Minecraft::Server.find_by!(public_id: attributes.fetch(:server_id))
        result = ::Minecraft::SetPlayerAccessRule.call(
          server: server,
          actor: current_user,
          desired_state: true,
          rule_type: attributes[:rule_type],
          username: attributes[:username],
          player_uuid: attributes[:player_uuid],
          reason: attributes[:reason],
          expires_at: attributes[:expires_at],
          idempotency_key: attributes[:idempotency_key],
          request_context: request_context
        )

        redirect_with_result(result, success_key: "player_access_rule_queued")
      rescue ActionController::ParameterMissing, KeyError
        redirect_to admin_minecraft_player_access_rules_path,
          alert: t("mcweb.services.errors.minecraft_access_rule_invalid")
      end

      def destroy
        result = ::Minecraft::SetPlayerAccessRule.call(
          server: @rule.server,
          actor: current_user,
          desired_state: false,
          rule: @rule,
          reason: params[:reason],
          idempotency_key: params[:idempotency_key],
          expected_lock_version: params[:lock_version],
          request_context: request_context
        )

        redirect_with_result(result, success_key: "player_access_rule_revoke_queued")
      end

      private

      def set_rule
        @rule = ::Minecraft::PlayerAccessRule.find_by_public_id!(params[:public_id])
      end

      def redirect_with_result(result, success_key:)
        if result.success?
          notice_key = result.value[:noop] ? "player_access_rule_unchanged" : success_key
          redirect_to admin_minecraft_player_access_rules_path,
            notice: t("mcweb.flash.#{notice_key}")
        else
          redirect_to admin_minecraft_player_access_rules_path,
            alert: service_error_message(result)
        end
      end

      def request_context
        {
          ip_address: request.remote_ip,
          user_agent: request.user_agent,
          request_id: request.request_id
        }
      end

      def connector_ready?(server)
        server.status == "online" &&
          server.last_heartbeat_at.present? &&
          server.last_heartbeat_at > 2.minutes.ago
      end

      def serialize_rule(rule)
        {
          id: rule.public_id,
          type: rule.rule_type,
          status: rule.status,
          username: rule.username,
          playerUuid: rule.player_uuid,
          reason: rule.reason,
          revokeReason: rule.revoke_reason,
          server: {
            id: rule.server.public_id,
            name: rule.server.name
          },
          createdBy: rule.created_by&.display_name,
          revokedBy: rule.revoked_by&.display_name,
          expiresAt: rule.expires_at&.iso8601,
          appliedAt: rule.applied_at&.iso8601,
          revokedAt: rule.revoked_at&.iso8601,
          failedAt: rule.failed_at&.iso8601,
          createdAt: rule.created_at.iso8601,
          applyTaskStatus: rule.apply_task&.status,
          revokeTaskStatus: rule.revoke_task&.status,
          lockVersion: rule.lock_version,
          canRevoke: rule.active?,
          revokeUrl: admin_minecraft_player_access_rule_path(rule)
        }
      end
    end
  end
end
