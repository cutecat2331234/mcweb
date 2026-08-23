# frozen_string_literal: true

module Admin
  module Minecraft
    class WorldRestoresController < BaseController
      include ServiceResponder

      before_action -> { require_permission("minecraft.world_restores.execute") }
      before_action :set_server
      before_action :set_plan, only: %i[authorize execute]
      before_action :prevent_response_storage

      def create
        backup = @server.world_backups.find_by!(public_id: params[:backup_id])
        result = ::Minecraft::PlanWorldRestore.call(
          server: @server,
          backup: backup,
          actor: current_user,
          reason: params[:reason],
          request_id: params[:request_id]
        )
        return render_service_error(result) if result.failure?

        value = result.value
        render json: {
          plan: serialize_plan(value.fetch(:plan)),
          confirmation: value.fetch(:confirmation),
          idempotent: value.fetch(:idempotent)
        }, status: value.fetch(:idempotent) ? :ok : :created
      end

      def authorize
        result = ::Minecraft::AuthorizeWorldRestore.call(
          plan: @plan,
          actor: current_user,
          password: params[:password],
          code: params[:code]
        )
        return render_service_error(result) if result.failure?

        render json: result.value.merge(plan: serialize_plan(@plan.reload))
      end

      def execute
        result = ::Minecraft::ExecuteWorldRestore.call(
          plan: @plan,
          actor: current_user,
          authorization_token: params[:authorization_token],
          confirmation: params[:confirmation]
        )
        return render_service_error(result) if result.failure?

        value = result.value
        render json: {
          plan: serialize_plan(value.fetch(:plan).reload),
          operation_id: value[:operation]&.public_id,
          idempotent: value.fetch(:idempotent),
          message: t("mcweb.admin.minecraft.world_restore_queued")
        }, status: value.fetch(:idempotent) ? :ok : :accepted
      end

      private

      def set_server
        @server = ::Minecraft::Server.find_by!(public_id: params[:server_id])
      end

      def set_plan
        @plan = @server.world_restore_plans.find_by!(public_id: params[:public_id])
      end

      def serialize_plan(plan)
        {
          id: plan.public_id,
          backup_id: plan.world_backup.public_id,
          pre_restore_backup_id: plan.pre_restore_world_backup&.public_id,
          status: plan.status,
          reason: plan.reason,
          expires_at: plan.expires_at.utc.iso8601(6),
          authorization_expires_at: plan.authorization_expires_at&.utc&.iso8601(6),
          phase: plan.result_summary.to_h["phase"],
          rolled_back: plan.result_summary.to_h["rolled_back"],
          recovery_required: plan.result_summary.to_h["recovery_required"],
          error_code: plan.error_code,
          authorize_url: authorize_admin_minecraft_server_world_restore_path(@server, plan),
          execute_url: execute_admin_minecraft_server_world_restore_path(@server, plan)
        }.compact
      end

      def render_service_error(result)
        render json: {
          error: service_error_message(result),
          code: result.code
        }.compact, status: error_status(result.code)
      end

      def error_status(code)
        value = code.to_s
        return :forbidden if value.end_with?("unauthorized")
        return :conflict if value.include?("stale") || value.include?("changed") ||
          value.include?("active") || value.include?("idempotency_conflict")

        :unprocessable_entity
      end

      def prevent_response_storage
        response.set_header("Cache-Control", "no-store")
        response.set_header("Pragma", "no-cache")
      end
    end
  end
end
