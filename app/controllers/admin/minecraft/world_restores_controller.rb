# frozen_string_literal: true

module Admin
  module Minecraft
    class WorldRestoresController < BaseController
      include ServiceResponder

      before_action -> { require_permission("minecraft.world_restores.execute") },
        only: %i[create authorize execute]
      before_action -> { require_permission("minecraft.world_restores.resolve_recovery") },
        only: %i[plan_recovery authorize_recovery execute_recovery]
      before_action :set_server
      before_action :set_plan, only: %i[
        authorize execute plan_recovery authorize_recovery execute_recovery
      ]
      before_action :set_resolution, only: %i[authorize_recovery execute_recovery]
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
          code: params[:code],
          ip_address: request.remote_ip
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

      def plan_recovery
        result = ::Minecraft::PlanWorldRestoreRecovery.call(
          plan: @plan,
          actor: current_user,
          resolution_action: params[:resolution_action],
          reason: params[:reason],
          request_id: params[:request_id],
          expected_plan_lock_version: params[:expected_plan_lock_version]
        )
        return render_service_error(result) if result.failure?

        value = result.value
        render json: {
          plan: serialize_plan(@plan.reload),
          resolution: serialize_resolution(value.fetch(:resolution)),
          confirmation: value.fetch(:confirmation),
          idempotent: value.fetch(:idempotent)
        }, status: value.fetch(:idempotent) ? :ok : :created
      end

      def authorize_recovery
        result = ::Minecraft::AuthorizeWorldRestoreRecovery.call(
          resolution: @resolution,
          actor: current_user,
          password: params[:password],
          code: params[:code],
          ip_address: request.remote_ip,
          expected_lock_version: params[:expected_lock_version]
        )
        return render_service_error(result) if result.failure?

        value = result.value
        render json: value.except(:resolution).merge(
          plan: serialize_plan(@plan.reload),
          resolution: serialize_resolution(value.fetch(:resolution))
        )
      end

      def execute_recovery
        result = ::Minecraft::ExecuteWorldRestoreRecovery.call(
          resolution: @resolution,
          actor: current_user,
          authorization_token: params[:authorization_token],
          confirmation: params[:confirmation],
          expected_lock_version: params[:expected_lock_version]
        )
        return render_service_error(result) if result.failure?

        value = result.value
        render json: {
          plan: serialize_plan(@plan.reload),
          resolution: serialize_resolution(value.fetch(:resolution).reload),
          operation_id: value[:operation]&.public_id,
          idempotent: value.fetch(:idempotent),
          message: t("mcweb.admin.minecraft.world_restore_recovery_queued")
        }, status: value.fetch(:idempotent) ? :ok : :accepted
      end

      private

      def set_server
        @server = ::Minecraft::Server.find_by!(public_id: params[:server_id])
      end

      def set_plan
        @plan = @server.world_restore_plans.find_by!(public_id: params[:public_id])
      end

      def set_resolution
        @resolution = @plan.recovery_resolutions.find_by!(public_id: params[:resolution_id])
      end

      def serialize_plan(plan)
        {
          id: plan.public_id,
          backup_id: plan.world_backup.public_id,
          pre_restore_backup_id: plan.pre_restore_world_backup&.public_id,
          status: plan.status,
          lock_version: plan.lock_version,
          reason: plan.reason,
          expires_at: plan.expires_at.utc.iso8601(6),
          authorization_expires_at: plan.authorization_expires_at&.utc&.iso8601(6),
          phase: plan.result_summary.to_h["phase"],
          rolled_back: plan.result_summary.to_h["rolled_back"],
          recovery_required: plan.result_summary.to_h["recovery_required"],
          error_code: plan.error_code,
          authorize_url: authorize_admin_minecraft_server_world_restore_path(@server, plan),
          execute_url: execute_admin_minecraft_server_world_restore_path(@server, plan),
          plan_recovery_url: plan_recovery_admin_minecraft_server_world_restore_path(@server, plan),
          recovery_resolution: serialize_resolution(plan.recovery_resolutions.recent.first)
        }.compact
      end

      def serialize_resolution(resolution)
        return unless resolution

        {
          id: resolution.public_id,
          status: resolution.status,
          resolution_action: resolution.resolution_action,
          reason: resolution.reason,
          lock_version: resolution.lock_version,
          created_at: resolution.created_at&.utc&.iso8601(6),
          authorization_expires_at: resolution.authorization_expires_at&.utc&.iso8601(6),
          error_code: resolution.error_code,
          recovery_resolution_proof: resolution.result_summary.to_h["recovery_resolution_proof"],
          verified_world_state: resolution.result_summary.to_h["verified_world_state"],
          authorize_url: authorize_recovery_admin_minecraft_server_world_restore_path(@server, @plan),
          execute_url: execute_recovery_admin_minecraft_server_world_restore_path(@server, @plan)
        }.compact
      end

      def render_service_error(result)
        apply_retry_after_header(result)
        render json: {
          error: service_error_message(result),
          code: result.code
        }.compact, status: error_status(result.code)
      end

      def error_status(code)
        value = code.to_s
        return :too_many_requests if value == "rate_limited"
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
