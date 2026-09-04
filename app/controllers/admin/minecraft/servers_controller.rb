# frozen_string_literal: true

module Admin
  module Minecraft
    class ServersController < BaseController
      include ServiceResponder
      before_action -> { require_permission("minecraft.servers.manage") }
      before_action :set_server, only: %i[
        show edit update destroy rotate_secret start stop restart exec_command console_command
        tail_logs sync_files
      ]

      def index
        servers = ::Minecraft::Server.includes(:node).order(:name)

        render inertia: "Admin/Generic/Index", props: {
          title: t("mcweb.admin.minecraft.servers"),
          alerts: minecraft_server_index_alerts,
          columns: [
            admin_column(:name, t("mcweb.admin.minecraft.col_name"), link: true),
            admin_column(:address, t("mcweb.admin.minecraft.col_address")),
            admin_column(:port, t("mcweb.admin.minecraft.col_port")),
            admin_column(:status, t("mcweb.admin.minecraft.col_status")),
            admin_column(:process_state, t("mcweb.admin.minecraft.col_process_state"))
          ],
          rows: servers.map do |server|
            admin_row(
              name: server.name,
              address: server.address.to_s,
              port: server.port.to_s,
              status: server_status_label(server.status),
              process_state: process_state_label(server.process_state),
              url: admin_minecraft_server_path(server)
            )
          end,
          actions: [ { label: t("mcweb.admin.minecraft.new_server"), href: new_admin_minecraft_server_path } ]
        }
      end

      def show
        connector_secret_once = flash.delete(:connector_secret_once)
        latest = @server.server_snapshots.order(created_at: :desc).first
        na = t("mcweb.labels.not_available")
        node_tasks = @server.node_tasks.order(created_at: :desc).limit(20)
        metrics_result = Minecraft::SerializeMetricHistory.call(server: @server)
        render inertia: "Admin/Minecraft/Servers/Show", props: {
          title: @server.name,
          connectorSecretOnce: connector_secret_once,
          server: {
            public_id: @server.public_id,
            name: @server.name,
            address: @server.address.to_s,
            port: @server.port,
            status: server_status_label(@server.status),
            process_state: process_state_label(@server.process_state),
            connection_mode: @server.connection_mode,
            node_name: @server.node&.name,
            node_id: @server.node&.public_id,
            node_url: @server.node ? admin_minecraft_node_path(@server.node) : nil,
            working_directory: @server.working_directory.presence || na,
            last_heartbeat: @server.last_heartbeat_at ? l(@server.last_heartbeat_at, format: :long) : na,
            online_players: latest ? "#{latest.online_players}/#{latest.max_players}" : na,
            tps: latest&.tps&.to_s || na,
            version: latest&.version || na,
            secret_fingerprint: @server.connector_secret_fingerprint.presence || t("mcweb.admin.minecraft.secret_not_generated"),
            plugin_config: plugin_config_snippet(@server),
            node_managed: @server.node_managed?
          },
          processMismatchAlert: @server.metadata["process_mismatch_alert"],
          metricHistory: metrics_result.success? ? metrics_result.value[:points] : [],
          nodeTasks: node_tasks.map { |task| serialize_node_task(task) },
          defaultLogPath: default_server_log_path(@server),
          controlUrls: control_urls(@server),
          worldSafety: world_safety_props(@server),
          backUrl: admin_minecraft_servers_path,
          actions: [
            { label: t("mcweb.admin.minecraft.action_edit"), href: edit_admin_minecraft_server_path(@server) },
            { label: t("mcweb.admin.minecraft.action_rotate_secret"), href: rotate_secret_admin_minecraft_server_path(@server), method: "post", confirm: t("mcweb.admin.minecraft.confirm_rotate_secret") },
            { label: t("mcweb.admin.minecraft.action_delete"), href: admin_minecraft_server_path(@server), method: "delete", confirm: t("mcweb.admin.minecraft.confirm_delete_server") }
          ]
        }
      end

      def start
        enqueue_control!(:start_instance, t("mcweb.flash.server_start_queued"), audit_action: "minecraft.server.start")
      end

      def stop
        unless current_user.permission?("minecraft.servers.control")
          redirect_to admin_minecraft_server_path(@server), alert: t("mcweb.flash.permission_denied")
          return
        end

        result = Minecraft::GracefulStopServer.call(server: @server)
        record_server_audit!("minecraft.server.stop", graceful: result.value&.dig(:graceful))
        redirect_after_control(result, t("mcweb.flash.server_stop_queued"))
      end

      def restart
        enqueue_control!(:restart_instance, t("mcweb.flash.server_restart_queued"), audit_action: "minecraft.server.restart")
      end

      def exec_command
        unless current_user.permission?("minecraft.servers.control")
          redirect_to admin_minecraft_server_path(@server), alert: t("mcweb.flash.permission_denied")
          return
        end
        command = params[:command].to_s.strip
        if command.blank?
          redirect_to admin_minecraft_server_path(@server), alert: t("mcweb.flash.command_required")
          return
        end

        validation = Minecraft::ValidateExecCommand.call(command: command, actor: current_user)
        unless validation.success?
          redirect_to admin_minecraft_server_path(@server), alert: validation.error
          return
        end

        result = enqueue_node_task!(:exec_command, { command: command, cwd: @server.working_directory, timeout: 120 })
        record_server_audit!("minecraft.server.exec", command: command) if result.success?
        redirect_after_control(result, t("mcweb.flash.command_queued"))
      end

      def console_command
        unless current_user.permission?("minecraft.servers.control")
          redirect_to admin_minecraft_server_path(@server), alert: t("mcweb.flash.permission_denied")
          return
        end
        command = params[:command].to_s.strip
        if command.blank?
          redirect_to admin_minecraft_server_path(@server), alert: t("mcweb.flash.command_required")
          return
        end

        result = Minecraft::EnqueueConsoleCommand.call(server: @server, command: command)
        record_server_audit!("minecraft.server.console", command: command) if result.success?
        redirect_after_control(result, t("mcweb.flash.console_command_queued"))
      end

      def sync_files
        unless current_user.permission?("minecraft.servers.control")
          redirect_to admin_minecraft_server_path(@server), alert: t("mcweb.flash.permission_denied")
          return
        end
        source_path = params[:source_path].to_s.strip
        if source_path.blank?
          redirect_to admin_minecraft_server_path(@server), alert: t("mcweb.flash.source_path_required")
          return
        end

        url_result = Minecraft::BuildFileSyncUrl.call(path: source_path)
        unless url_result.success?
          redirect_to admin_minecraft_server_path(@server), alert: url_result.error
          return
        end

        dest = params[:destination].presence || File.join(@server.working_directory.to_s, File.basename(source_path))
        result = enqueue_node_task!(:sync_files, {
          url: url_result.value[:url],
          destination: dest
        })
        record_server_audit!("minecraft.server.sync_files", source: source_path, destination: dest) if result.success?
        redirect_after_control(result, t("mcweb.flash.sync_files_queued"))
      end

      def tail_logs
        unless current_user.permission?("minecraft.servers.control")
          redirect_to admin_minecraft_server_path(@server), alert: t("mcweb.flash.permission_denied")
          return
        end
        path = params[:path].to_s.strip
        path = default_server_log_path(@server) if path.blank?
        lines = params[:lines].to_i
        lines = 100 if lines <= 0

        result = enqueue_node_task!(:tail_logs, { path: path, lines: lines })
        redirect_after_control(result, t("mcweb.flash.tail_logs_queued"))
      end

      def rotate_secret
        secret = @server.generate_connector_secret!
        record_server_audit!("minecraft.server.rotate_secret")
        flash[:connector_secret_once] = secret
        redirect_to admin_minecraft_server_path(@server), notice: t("mcweb.flash.connector_secret_rotated")
      end

      def new
        render inertia: "Admin/Minecraft/Servers/Form", props: form_props(::Minecraft::Server.new(status: :offline, port: 25565))
      end

      def create
        @server = ::Minecraft::Server.new(parsed_server_params)

        if @server.save
          redirect_to admin_minecraft_server_path(@server), notice: t("mcweb.flash.created", resource: t("mcweb.resources.server"))
        else
          render inertia: "Admin/Minecraft/Servers/Form", props: form_props(@server), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Minecraft/Servers/Form", props: form_props(@server)
      end

      def update
        updated = false
        ::Minecraft::Server.transaction do
          @server.lock!
          @server.assign_attributes(parsed_server_params)
          updated = @server.save
          raise ActiveRecord::Rollback unless updated
        end

        if updated
          redirect_to admin_minecraft_server_path(@server), notice: t("mcweb.flash.updated", resource: t("mcweb.resources.server"))
        else
          render inertia: "Admin/Minecraft/Servers/Form", props: form_props(@server), status: :unprocessable_entity
        end
      end

      def destroy
        @server.destroy!
        redirect_to admin_minecraft_servers_path, notice: t("mcweb.flash.deleted", resource: t("mcweb.resources.server"))
      end

      private

      def set_server
        @server = ::Minecraft::Server.find_by!(public_id: params[:id])
      end

      def parsed_server_params
        permitted = server_params
        if permitted[:process_config].is_a?(String)
          raw = permitted[:process_config].strip
          permitted[:process_config] = raw.present? ? JSON.parse(raw) : {}
        end
        if permitted[:minecraft_node_id].blank?
          permitted[:minecraft_node_id] = nil
        end
        metadata = (@server&.metadata || {}).dup
        %w[
          graceful_stop_enabled graceful_stop_countdown graceful_stop_message graceful_stop_commands
          graceful_stop_timeout restart_schedule backup_enabled backup_schedule world_directory
        ].each do |key|
          metadata[key] = permitted.delete(key) if permitted.key?(key)
        end
        permitted[:metadata] = metadata if metadata != (@server&.metadata || {})
        permitted
      rescue JSON::ParserError
        @server ||= ::Minecraft::Server.new
        @server.errors.add(:process_config, I18n.t("mcweb.validation_errors.invalid_json"))
        server_params.except(:process_config)
      end

      def server_params
        params.expect(server: %i[
          name address port status minecraft_node_id connection_mode proxy_listen_url
          process_driver process_config working_directory
          graceful_stop_enabled graceful_stop_countdown graceful_stop_message graceful_stop_commands
          graceful_stop_timeout restart_schedule backup_enabled backup_schedule world_directory
        ])[:server]
      end

      def form_props(server)
        suggest = Minecraft::SuggestLeastLoadedNode.call
        meta = server.metadata || {}
        {
          title: server.persisted? ? t("mcweb.admin.minecraft.edit_server") : t("mcweb.admin.minecraft.new_server"),
          server: {
            name: server.name.to_s,
            address: server.address.to_s,
            port: server.port || 25565,
            status: server.status || "offline",
            minecraft_node_id: server.minecraft_node_id&.to_s || suggest.value&.dig(:node)&.id&.to_s || "",
            connection_mode: server.connection_mode || "direct",
            proxy_listen_url: server.proxy_listen_url.to_s,
            process_driver: server.process_driver.to_s,
            process_config: server.process_config.present? ? JSON.pretty_generate(server.process_config) : "",
            working_directory: server.working_directory.to_s,
            graceful_stop_enabled: meta["graceful_stop_enabled"].nil? ? "" : meta["graceful_stop_enabled"].to_s,
            graceful_stop_countdown: meta["graceful_stop_countdown"].to_s,
            graceful_stop_message: meta["graceful_stop_message"].to_s,
            graceful_stop_commands: Array(meta["graceful_stop_commands"]).join(","),
            graceful_stop_timeout: meta["graceful_stop_timeout"].to_s,
            restart_schedule: meta["restart_schedule"].to_s,
            backup_enabled: meta["backup_enabled"].nil? ? "" : meta["backup_enabled"].to_s,
            backup_schedule: meta["backup_schedule"].to_s,
            world_directory: meta["world_directory"].presence || "world"
          },
          suggestedNode: suggest.value&.dig(:node)&.name,
          statusOptions: ::Minecraft::Server.statuses.keys.map { |s| { value: s, label: server_status_label(s) } },
          connectionModeOptions: ::Minecraft::Server.connection_modes.keys.map { |s| { value: s, label: s } },
          processDriverOptions: ::Minecraft::Server::PROCESS_DRIVERS.map { |d| { value: d, label: d } },
          nodeOptions: ::Minecraft::Node.order(:name).map { |n| { value: n.id.to_s, label: n.name } },
          submitUrl: server.persisted? ? admin_minecraft_server_path(server) : admin_minecraft_servers_path,
          method: server.persisted? ? "patch" : "post",
          backUrl: admin_minecraft_servers_path,
          errors: server.errors.to_hash
        }
      end

      def enqueue_control!(task_type, notice, payload: {}, audit_action: nil)
        unless current_user.permission?("minecraft.servers.control")
          redirect_to admin_minecraft_server_path(@server), alert: t("mcweb.flash.permission_denied")
          return
        end
        result = enqueue_node_task!(task_type, payload)
        record_server_audit!(audit_action, payload) if audit_action && result.success?
        redirect_after_control(result, notice)
      end

      def enqueue_node_task!(task_type, payload = {})
        unless @server.node_managed?
          return ServiceResult.failure(error: I18n.t("mcweb.user_copy.server_not_bound_to_node"))
        end

        Minecraft::EnqueueNodeTask.call(
          node: @server.node,
          server: @server,
          task_type: task_type,
          payload: payload
        )
      end

      def redirect_after_control(result, notice)
        if result.success?
          redirect_to admin_minecraft_server_path(@server), notice: notice
        else
          redirect_to admin_minecraft_server_path(@server), alert: service_error_message(result)
        end
      end

      def control_urls(server)
        return {} unless server.node_managed?

        {
          start: start_admin_minecraft_server_path(server),
          stop: stop_admin_minecraft_server_path(server),
          restart: restart_admin_minecraft_server_path(server),
          exec: exec_command_admin_minecraft_server_path(server),
          console: console_command_admin_minecraft_server_path(server),
          tail_logs: tail_logs_admin_minecraft_server_path(server),
          sync_files: sync_files_admin_minecraft_server_path(server)
        }
      end

      def world_safety_props(server)
        can_backup = current_user.permission?("minecraft.world_backups.manage")
        can_restore = current_user.permission?("minecraft.world_restores.execute")
        can_resolve_recovery = current_user.permission?("minecraft.world_restores.resolve_recovery")
        visible = can_backup || can_restore || can_resolve_recovery
        node = server.node
        recovery_required = ActiveModel::Type::Boolean.new.cast(
          node&.metadata.to_h.fetch("world_restore_recovery_required", false)
        )
        common_blockers = []
        common_blockers << "node_unmanaged" unless node
        common_blockers << "server_not_stopped" unless server.process_state_stopped?
        common_blockers << "working_directory_missing" if server.working_directory.blank?
        common_blockers << "node_stale" if node && !node.fresh_heartbeat?
        common_blockers << "recovery_required" if recovery_required
        common_blockers << "active_restore" if server.world_restore_plans.active.exists?

        path_result = ::Minecraft::WorldPathPolicy.call(server.metadata["world_directory"].presence || "world")
        common_blockers << "world_path_invalid" if path_result.failure?
        backup_blockers = common_blockers.dup
        restore_blockers = common_blockers.dup
        backup_blockers << "backup_capability_missing" if node && !node.supports_managed_world_backups_v2?
        restore_blockers << "restore_capability_missing" if node && !(
          node.supports_managed_world_backups_v2? && node.supports_world_restore_v2?
        )
        recovery_blockers = []
        recovery_blockers << "node_unmanaged" unless node
        recovery_blockers << "server_not_stopped" unless server.process_state_stopped?
        recovery_blockers << "working_directory_missing" if server.working_directory.blank?
        recovery_blockers << "node_stale" if node && !node.fresh_heartbeat?
        recovery_blockers << "recovery_capability_missing" if node && !node.supports_world_restore_recovery_v2?

        {
          visible: visible,
          can_create_backup: can_backup,
          can_restore: can_restore,
          can_resolve_recovery: can_resolve_recovery,
          create_backup_url: can_backup ? admin_minecraft_server_world_backups_path(server) : nil,
          create_restore_url: can_restore ? admin_minecraft_server_world_restores_path(server) : nil,
          refresh_url: admin_minecraft_server_path(server),
          start_blocked: server.world_restore_blocks_start?,
          backup_blockers: backup_blockers.uniq,
          restore_blockers: restore_blockers.uniq,
          recovery_blockers: recovery_blockers.uniq,
          backups: visible ? server.world_backups.recent.limit(50).map { |backup| serialize_world_backup(backup) } : [],
          plans: (can_restore || can_resolve_recovery) ? server.world_restore_plans.recent.limit(20).map { |plan| serialize_world_restore_plan(server, plan) } : []
        }
      end

      def serialize_world_backup(backup)
        {
          id: backup.public_id,
          purpose: backup.purpose,
          status: backup.status,
          restorable: backup.restorable?,
          target_compatible: backup.manifest_summary.to_h["world_relative_path"] ==
            (@server.metadata["world_directory"].presence || "world"),
          created_at: backup.created_at&.utc&.iso8601(6),
          verified_at: backup.verified_at&.utc&.iso8601(6),
          archive_bytes: backup.archive_bytes,
          uncompressed_bytes: backup.uncompressed_bytes,
          entry_count: backup.entry_count,
          manifest_digest_short: backup.manifest_digest&.last(12),
          world_relative_path: backup.manifest_summary.to_h["world_relative_path"],
          error_code: backup.error_code
        }.compact
      end

      def serialize_world_restore_plan(server, plan)
        expired = world_restore_plan_expired?(plan)
        own_action = current_user.permission?("minecraft.world_restores.execute") &&
          plan.actor_id == current_user.id
        resumable = own_action && plan.status.in?(%w[planned authorized]) && !expired
        can_resolve = current_user.permission?("minecraft.world_restores.resolve_recovery")
        resolution = plan.recovery_resolutions.recent.first
        {
          id: plan.public_id,
          backup_id: plan.world_backup.public_id,
          pre_restore_backup_id: plan.pre_restore_world_backup&.public_id,
          status: plan.status,
          lock_version: plan.lock_version,
          reason: plan.reason,
          created_at: plan.created_at&.utc&.iso8601(6),
          expires_at: plan.expires_at&.utc&.iso8601(6),
          phase: plan.result_summary.to_h["phase"],
          rolled_back: plan.result_summary.to_h["rolled_back"],
          recovery_required: plan.result_summary.to_h["recovery_required"],
          error_code: plan.error_code,
          resumable: resumable,
          is_expired: expired,
          authorize_url: resumable ? authorize_admin_minecraft_server_world_restore_path(server, plan) : nil,
          execute_url: resumable && plan.status_authorized? ?
            execute_admin_minecraft_server_world_restore_path(server, plan) : nil,
          cancel_url: resumable ? cancel_admin_minecraft_server_world_restore_path(server, plan) : nil,
          plan_recovery_url: can_resolve && plan.status_recovery_required? ?
            plan_recovery_admin_minecraft_server_world_restore_path(server, plan) : nil,
          recovery_resolution: serialize_world_restore_resolution(server, plan, resolution, can_resolve: can_resolve)
        }.compact
      end

      def serialize_world_restore_resolution(server, plan, resolution, can_resolve:)
        return unless resolution

        expired = world_restore_resolution_expired?(resolution)
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
            authorize_recovery_admin_minecraft_server_world_restore_path(server, plan) : nil,
          execute_url: resumable && resolution.status_authorized? ?
            execute_recovery_admin_minecraft_server_world_restore_path(server, plan) : nil,
          cancel_url: can_resolve && resolution.status.in?(%w[planned authorized]) && !expired ?
            cancel_recovery_admin_minecraft_server_world_restore_path(server, plan) : nil,
          takeover_url: can_resolve && resolution.status.in?(%w[planned authorized]) && !expired ?
            takeover_recovery_admin_minecraft_server_world_restore_path(server, plan) : nil
        }.compact
      end

      def world_restore_plan_expired?(plan, now = Time.current)
        plan.status_expired? || (
          plan.status.in?(%w[planned authorized]) && plan.expires_at <= now
        )
      end

      def world_restore_resolution_expired?(resolution, now = Time.current)
        resolution.status_expired? || resolution.expired_by_time?(now)
      end

      def record_server_audit!(action, metadata = {})
        Minecraft::RecordServerAudit.call(
          action: action,
          actor: current_user,
          server: @server,
          metadata: metadata,
          request: request
        )
      end

      def default_server_log_path(server)
        meta_path = server.metadata["default_log_path"].presence
        return meta_path if meta_path

        wd = server.working_directory.presence
        wd ? File.join(wd, "logs", "latest.log") : "logs/latest.log"
      end

      def minecraft_server_index_alerts
        alerts = []
        stale_nodes = ::Minecraft::Node.where(status: :online)
          .where("last_heartbeat_at IS NULL OR last_heartbeat_at < ?", 3.minutes.ago).count
        if stale_nodes.positive?
          alerts << {
            level: "warning",
            message: t("mcweb.admin.minecraft.alert_stale_nodes", count: stale_nodes)
          }
        end

        mismatched = ::Minecraft::Server.managed_by_node.where("metadata ? 'process_mismatch_alert'").count
        if mismatched.positive?
          alerts << {
            level: "warning",
            message: t("mcweb.admin.minecraft.alert_process_mismatch", count: mismatched)
          }
        end
        alerts
      end

      def plugin_config_snippet(server)
        {
          website_url: server.plugin_website_url(request.base_url),
          server_id: server.public_id,
          connector_secret: server.connector_secret.present? ? "••••••••" : ""
        }
      end

      def server_status_label(status)
        key = "mcweb.admin.minecraft.status_#{status}"
        I18n.exists?(key) ? t(key) : status.to_s
      end

      def process_state_label(state)
        key = "mcweb.admin.minecraft.process_state_#{state}"
        I18n.exists?(key) ? t(key) : state.to_s
      end
    end
  end
end
