# frozen_string_literal: true

module Admin
  module System
    class DeveloperWorkbenchController < BaseController
      prepend_before_action :require_developer_mode!
      before_action -> { require_permission("system.settings.manage") }

      def show
        snapshot = Operations::DeveloperWorkbenchSnapshot.call(
          capture_kind: params[:capture_kind].presence || "mail",
          capture_page: params[:capture_page].presence || 1
        )
        render inertia: "Admin/System/DeveloperWorkbench/Show", props:
          snapshot.merge(
            workbenchUrl: admin_system_developer_workbench_path,
            settingsUrl: admin_system_settings_path,
            jobsUrl: admin_system_jobs_path,
            diagnosticUrl: diagnostic_admin_system_developer_workbench_path,
            clearCapturesUrl:
              clear_captures_admin_system_developer_workbench_path,
            seedScenarioUrl:
              seed_scenario_admin_system_developer_workbench_path,
            attachmentScenarioUrl:
              inject_attachment_state_admin_system_developer_workbench_path,
            runTaskUrl: run_task_admin_system_developer_workbench_path,
            personaSwitchUrl: developer_mode_switch_persona_path
          )
      end

      def diagnostic
        payload = Operations::DeveloperWorkbenchSnapshot.call.fetch(
          :diagnostics
        )
        send_data(
          JSON.pretty_generate(payload),
          type: "application/json",
          disposition: "attachment",
          filename: "mcweb-developer-diagnostics.json"
        )
      end

      def clear_captures
        requested_kind = params[:kind].presence || "all"
        Administration::AuditLogger.call(
          actor: current_user,
          action: "developer_mode.captures_clear_requested",
          metadata: { kind: requested_kind },
          ip_address: request.remote_ip,
          user_agent: request.user_agent,
          request_id: request.request_id
        )
        result = Operations::DeveloperCaptureStore.new.clear!(
          kind: requested_kind
        )
        Administration::AuditLogger.call(
          actor: current_user,
          action: "developer_mode.captures_cleared",
          metadata: {
            kinds: result.fetch(:kinds),
            deleted_files: result.fetch(:deletedFiles),
            deleted_bytes: result.fetch(:deletedBytes)
          },
          ip_address: request.remote_ip,
          user_agent: request.user_agent,
          request_id: request.request_id
        )
        redirect_back(
          fallback_location: admin_system_developer_workbench_path,
          notice: t(
            "mcweb.flash.developer_mode_captures_cleared",
            count: result.fetch(:deletedFiles)
          )
        )
      rescue ArgumentError
        redirect_back(
          fallback_location: admin_system_developer_workbench_path,
          alert: t("mcweb.flash.developer_mode_capture_kind_invalid")
        )
      end

      def seed_scenario
        result = Operations::DeveloperScenarioSeeder.call(
          scenario: params[:scenario],
          actor: current_user
        )
        return developer_tool_failure(result) if result.failure?

        redirect_back(
          fallback_location: admin_system_developer_workbench_path,
          notice: t("mcweb.flash.developer_mode_scenario_seeded")
        )
      end

      def inject_attachment_state
        upload = Community::Upload.find_by(
          public_id: params[:upload_public_id].to_s.strip
        )
        result = Operations::DeveloperUploadScenario.call(
          upload: upload,
          scenario: params[:scenario],
          actor: current_user
        )
        return developer_tool_failure(result) if result.failure?

        redirect_back(
          fallback_location: admin_system_developer_workbench_path,
          notice: t("mcweb.flash.developer_mode_attachment_state_applied")
        )
      end

      def run_task
        result = Operations::DeveloperTaskRunner.call(
          task: params[:task],
          actor: current_user
        )
        return developer_tool_failure(result) if result.failure?

        redirect_back(
          fallback_location: admin_system_developer_workbench_path,
          notice: t("mcweb.flash.developer_mode_task_enqueued")
        )
      end

      private

      def require_developer_mode!
        head :not_found unless Mcweb::DeveloperMode.enabled?
      end

      def developer_tool_failure(_result)
        redirect_back(
          fallback_location: admin_system_developer_workbench_path,
          alert: t("mcweb.flash.developer_mode_tool_failed")
        )
      end
    end
  end
end
