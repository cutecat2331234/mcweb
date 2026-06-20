# frozen_string_literal: true

module Admin
  module Minecraft
    class NodesController < BaseController
      before_action -> { require_permission("minecraft.nodes.manage") }
      before_action :set_node, only: %i[show edit update destroy rotate_secret generate_pairing_token]

      def index
        nodes = ::Minecraft::Node.order(:name)

        render inertia: "Admin/Generic/Index", props: {
          title: t("mcweb.admin.minecraft.nodes"),
          columns: [
            admin_column(:name, t("mcweb.admin.minecraft.col_name"), link: true),
            admin_column(:hostname, t("mcweb.admin.minecraft.col_hostname")),
            admin_column(:status, t("mcweb.admin.minecraft.col_status"))
          ],
          rows: nodes.map do |node|
            admin_row(
              name: node.name,
              hostname: node.hostname.to_s,
              status: node_status_label(node.status),
              url: admin_minecraft_node_path(node)
            )
          end,
          actions: [ { label: t("mcweb.admin.minecraft.new_node"), href: new_admin_minecraft_node_path } ]
        }
      end

      def show
        node_secret_once = flash.delete(:node_secret_once)
        pairing_token_once = flash.delete(:pairing_token_once)
        pairing_token_expires_at = flash.delete(:pairing_token_expires_at)
        node_tasks = @node.node_tasks.order(created_at: :desc).limit(20)
        metadata = @node.metadata || {}
        metrics_result = Minecraft::SerializeMetricHistory.call(node: @node)
        render inertia: "Admin/Minecraft/Nodes/Show", props: {
          title: @node.name,
          nodeSecretOnce: node_secret_once,
          pairingTokenOnce: pairing_token_once,
          pairingTokenExpiresAt: pairing_token_expires_at,
          node: serialize_node(@node),
          connectorProxy: metadata["connector_proxy"],
          hostMetrics: metadata["host_metrics"].presence || host_metrics_from_metadata(metadata),
          metricHistory: metrics_result.success? ? metrics_result.value[:points] : [],
          nodeTasks: node_tasks.map { |task| serialize_node_task(task) },
          alerts: node_alerts(@node),
          servers: @node.servers.order(:name).map { |s| serialize_server_summary(s) },
          backUrl: admin_minecraft_nodes_path,
          actions: [
            { label: t("mcweb.admin.minecraft.action_edit"), href: edit_admin_minecraft_node_path(@node) },
            { label: t("mcweb.admin.minecraft.action_generate_pairing_token"), href: generate_pairing_token_admin_minecraft_node_path(@node), method: "post" },
            { label: t("mcweb.admin.minecraft.action_rotate_node_secret"), href: rotate_secret_admin_minecraft_node_path(@node), method: "post", confirm: t("mcweb.admin.minecraft.confirm_rotate_node_secret") },
            { label: t("mcweb.admin.minecraft.action_delete"), href: admin_minecraft_node_path(@node), method: "delete", confirm: t("mcweb.admin.minecraft.confirm_delete_node") }
          ]
        }
      end

      def rotate_secret
        secret = @node.generate_node_secret!
        flash[:node_secret_once] = secret
        redirect_to admin_minecraft_node_path(@node), notice: t("mcweb.flash.node_secret_generated")
      end

      def generate_pairing_token
        result = Minecraft::GeneratePairingToken.call(node: @node)
        if result.success?
          flash[:pairing_token_once] = result.value[:token]
          flash[:pairing_token_expires_at] = result.value[:expires_at]
          redirect_to admin_minecraft_node_path(@node),
            notice: t("mcweb.flash.pairing_token_generated", expires: result.value[:expires_at])
        else
          redirect_to admin_minecraft_node_path(@node), alert: service_error_message(result)
        end
      end

      def new
        render inertia: "Admin/Minecraft/Nodes/Form", props: form_props(::Minecraft::Node.new(status: :offline))
      end

      def create
        @node = ::Minecraft::Node.new(node_params)

        if @node.save
          redirect_to admin_minecraft_node_path(@node), notice: t("mcweb.flash.created", resource: t("mcweb.resources.node"))
        else
          render inertia: "Admin/Minecraft/Nodes/Form", props: form_props(@node), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Minecraft/Nodes/Form", props: form_props(@node)
      end

      def update
        if @node.update(node_params)
          redirect_to admin_minecraft_node_path(@node), notice: t("mcweb.flash.updated", resource: t("mcweb.resources.node"))
        else
          render inertia: "Admin/Minecraft/Nodes/Form", props: form_props(@node), status: :unprocessable_entity
        end
      end

      def destroy
        @node.destroy!
        redirect_to admin_minecraft_nodes_path, notice: t("mcweb.flash.deleted", resource: t("mcweb.resources.node"))
      end

      private

      def set_node
        @node = ::Minecraft::Node.find_by!(public_id: params[:id])
      end

      def node_params
        params.expect(node: %i[name hostname status proxy_listen_url])[:node]
      end

      def form_props(node)
        {
          title: node.persisted? ? t("mcweb.admin.minecraft.edit_node") : t("mcweb.admin.minecraft.new_node"),
          node: {
            name: node.name.to_s,
            hostname: node.hostname.to_s,
            status: node.status || "offline",
            proxy_listen_url: node.proxy_listen_url.to_s.presence || "http://127.0.0.1:9876"
          },
          statusOptions: ::Minecraft::Node.statuses.keys.map { |s| { value: s, label: node_status_label(s) } },
          submitUrl: node.persisted? ? admin_minecraft_node_path(node) : admin_minecraft_nodes_path,
          method: node.persisted? ? "patch" : "post",
          backUrl: admin_minecraft_nodes_path,
          errors: node.errors.to_hash
        }
      end

      def node_status_label(status)
        key = "mcweb.admin.minecraft.status_#{status}"
        I18n.exists?(key) ? t(key) : status.to_s
      end

      def serialize_node(node)
        na = t("mcweb.labels.not_available")
        {
          public_id: node.public_id,
          name: node.name,
          hostname: node.hostname.to_s,
          status: node_status_label(node.status),
          secret_fingerprint: node.node_secret_fingerprint.presence || t("mcweb.admin.minecraft.secret_not_generated"),
          last_heartbeat_at: node.last_heartbeat_at ? l(node.last_heartbeat_at, format: :long) : na,
          last_heartbeat_at_iso: node.last_heartbeat_at&.iso8601,
          proxy_listen_url: node.effective_proxy_listen_url
        }
      end

      def host_metrics_from_metadata(metadata)
        keys = %w[go_version num_cpu os arch mem_alloc_mb]
        metrics = metadata.slice(*keys)
        metrics.presence
      end

      def node_alerts(node)
        alerts = []
        if node.status == "offline"
          alerts << { level: "error", message: t("mcweb.admin.minecraft.alert_node_offline") }
        end
        if minecraft_node_stale?(node)
          alerts << { level: "warning", message: t("mcweb.admin.minecraft.alert_node_stale") }
        end
        alerts
      end

      def serialize_server_summary(server)
        {
          name: server.name,
          public_id: server.public_id,
          process_state: server.process_state,
          url: admin_minecraft_server_path(server)
        }
      end
    end
  end
end
