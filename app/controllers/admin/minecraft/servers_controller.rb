# frozen_string_literal: true

module Admin
  module Minecraft
    class ServersController < BaseController
      include ServiceResponder
      before_action -> { require_permission("minecraft.servers.manage") }
      before_action :set_server, only: %i[
        show edit update destroy rotate_secret start stop restart exec_command console_command
        tail_logs backup_world restore_world sync_files
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

      def backup_world
        enqueue_control!(
          :backup_world,
          t("mcweb.flash.backup_queued"),
          audit_action: "minecraft.server.backup",
          payload: backup_payload
        )
      end

      def restore_world
        archive = params[:archive].to_s.strip
        if archive.blank?
          redirect_to admin_minecraft_server_path(@server), alert: t("mcweb.flash.archive_required")
          return
        end

        enqueue_control!(
          :restore_world,
          t("mcweb.flash.restore_queued"),
          audit_action: "minecraft.server.restore",
          payload: { archive: archive }
        )
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
        if @server.update(parsed_server_params)
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
          graceful_stop_timeout restart_schedule backup_enabled backup_schedule backup_directory world_directory
        ].each do |key|
          metadata[key] = permitted.delete(key) if permitted.key?(key)
        end
        permitted[:metadata] = metadata if metadata != (@server&.metadata || {})
        permitted
      rescue JSON::ParserError
        @server ||= ::Minecraft::Server.new
        @server.errors.add(:process_config, "invalid JSON")
        server_params.except(:process_config)
      end

      def server_params
        params.expect(server: %i[
          name address port status minecraft_node_id connection_mode proxy_listen_url
          process_driver process_config working_directory
          graceful_stop_enabled graceful_stop_countdown graceful_stop_message graceful_stop_commands
          graceful_stop_timeout restart_schedule backup_enabled backup_schedule backup_directory world_directory
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
            backup_directory: meta["backup_directory"].to_s,
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
          return ServiceResult.failure(error: "Server is not bound to a node.")
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
          backup: backup_world_admin_minecraft_server_path(server),
          restore: restore_world_admin_minecraft_server_path(server),
          sync_files: sync_files_admin_minecraft_server_path(server)
        }
      end

      def backup_payload
        backup_dir = @server.metadata["backup_directory"].presence ||
          File.join(@server.working_directory.to_s, "backups")
        filename = "world-#{Time.current.strftime('%Y%m%d-%H%M%S')}.tar.gz"
        {
          source: @server.metadata["world_directory"].presence || "world",
          destination: File.join(backup_dir, filename)
        }
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
