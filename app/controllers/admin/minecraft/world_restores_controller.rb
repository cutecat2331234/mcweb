# frozen_string_literal: true

module Admin
  module Minecraft
    class WorldRestoresController < BaseController
      include ServiceResponder

      before_action -> { require_permission("minecraft.world_restores.execute") },
        only: %i[create authorize execute cancel]
      before_action -> { require_permission("minecraft.world_restores.resolve_recovery") },
        only: %i[
          plan_recovery authorize_recovery execute_recovery cancel_recovery takeover_recovery
        ]
      before_action :set_server
      before_action :set_plan, only: %i[
        authorize execute cancel plan_recovery authorize_recovery execute_recovery
        cancel_recovery takeover_recovery
      ]
      before_action :set_resolution, only: %i[
        authorize_recovery execute_recovery cancel_recovery takeover_recovery
      ]
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

      def cancel
        result = ::Minecraft::CancelWorldRestore.call(
          plan: @plan,
          actor: current_user,
          reason: params[:reason],
          request_id: params[:request_id],
          expected_lock_version: params[:expected_lock_version]
        )
        return render_service_error(result) if result.failure?

        value = result.value
        render json: {
          plan: serialize_plan(value.fetch(:plan).reload),
          idempotent: value.fetch(:idempotent),
          message: t("mcweb.admin.minecraft.world_restore_cancelled")
        }, status: :ok
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

      def cancel_recovery
        render_recovery_lifecycle("cancel")
      end

      def takeover_recovery
        render_recovery_lifecycle("takeover")
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
        expired = restore_plan_expired?(plan)
        can_execute = current_user.permission?("minecraft.world_restores.execute")
        own_action = can_execute && plan.actor_id == current_user.id
        resumable = own_action && plan.status.in?(%w[planned authorized]) && !expired
        can_resolve = current_user.permission?("minecraft.world_restores.resolve_recovery")
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
          resumable: resumable,
          is_expired: expired,
          authorize_url: resumable ?
            authorize_admin_minecraft_server_world_restore_path(@server, plan) : nil,
          execute_url: resumable && plan.status_authorized? ?
            execute_admin_minecraft_server_world_restore_path(@server, plan) : nil,
          cancel_url: resumable ?
            cancel_admin_minecraft_server_world_restore_path(@server, plan) : nil,
          plan_recovery_url: can_resolve && plan.status_recovery_required? ?
            plan_recovery_admin_minecraft_server_world_restore_path(@server, plan) : nil,
          recovery_resolution: serialize_resolution(plan.recovery_resolutions.recent.first)
        }.compact
      end

      def serialize_resolution(resolution)
        return unless resolution

        expired = restore_resolution_expired?(resolution)
        can_resolve = current_user.permission?("minecraft.world_restores.resolve_recovery")
        own_action = resolution.actor_id == current_user.id
        resumable = can_resolve && own_action && resolution.status.in?(%w[planned authorized]) && !expired
        {
          id: resolution.public_id,
          status: resolution.status,
          resolution_action: resolution.resolution_action,
          reason: resolution.reason,
          lock_version: resolution.lock_version,
          created_at: resolution.created_at&.utc&.iso8601(6),
          expires_at: resolution.expires_at&.utc&.iso8601(6),
          authorization_expires_at: resolution.authorization_expires_at&.utc&.iso8601(6),
          expired_at: resolution.expired_at&.utc&.iso8601(6),
          lifecycle_action: resolution.lifecycle_action,
          lifecycle_reason: resolution.lifecycle_reason,
          lifecycle_actor_id: resolution.lifecycle_actor&.public_id,
          supersedes_resolution_id: resolution.superseded_resolution&.public_id,
          error_code: resolution.error_code,
          recovery_resolution_proof: resolution.result_summary.to_h["recovery_resolution_proof"],
          verified_world_state: resolution.result_summary.to_h["verified_world_state"],
          resumable: resumable,
          is_expired: expired,
          authorize_url: resumable ?
            authorize_recovery_admin_minecraft_server_world_restore_path(@server, @plan) : nil,
          execute_url: resumable && resolution.status_authorized? ?
            execute_recovery_admin_minecraft_server_world_restore_path(@server, @plan) : nil,
          cancel_url: can_resolve && resolution.status.in?(%w[planned authorized]) && !expired ?
            cancel_recovery_admin_minecraft_server_world_restore_path(@server, @plan) : nil,
          takeover_url: can_resolve && resolution.status.in?(%w[planned authorized]) && !expired ?
            takeover_recovery_admin_minecraft_server_world_restore_path(@server, @plan) : nil
        }.compact
      end

      def restore_plan_expired?(plan, now = Time.current)
        plan.status_expired? || (
          plan.status.in?(%w[planned authorized]) && plan.expires_at <= now
        )
      end

      def restore_resolution_expired?(resolution, now = Time.current)
        resolution.status_expired? || resolution.expired_by_time?(now)
      end

      def render_recovery_lifecycle(action)
        result = ::Minecraft::ManageWorldRestoreRecoveryResolution.call(
          resolution: @resolution,
          actor: current_user,
          lifecycle_action: action,
          resolution_action: params[:resolution_action],
          reason: params[:reason],
          request_id: params[:request_id],
          expected_plan_lock_version: params[:expected_plan_lock_version],
          expected_resolution_lock_version: params[:expected_resolution_lock_version],
          password: params[:password],
          code: params[:code],
          ip_address: request.remote_ip
        )
        return render_service_error(result) if result.failure?

        value = result.value
        render json: {
          plan: serialize_plan(@plan.reload),
          resolution: serialize_resolution(value.fetch(:resolution).reload),
          replacement: serialize_resolution(value[:replacement]&.reload),
          confirmation: value[:confirmation],
          idempotent: value.fetch(:idempotent),
          message: t("mcweb.admin.minecraft.world_restore_recovery_lifecycle_#{action}")
        }.compact, status: value.fetch(:idempotent) ? :ok : :accepted
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
          value.include?("active") || value.include?("idempotency_conflict") ||
          value.include?("not_cancellable")

        :unprocessable_entity
      end

      def prevent_response_storage
        response.set_header("Cache-Control", "no-store")
        response.set_header("Pragma", "no-cache")
      end
    end
  end
end
