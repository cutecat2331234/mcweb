# frozen_string_literal: true

module Admin
  module Minecraft
    class ServersController < BaseController
      before_action -> { require_permission("minecraft.servers.manage") }
      before_action -> { require_admin_module!("minecraft") }
      before_action :set_server, only: %i[show edit update destroy rotate_secret]

      def index
        servers = ::Minecraft::Server.order(:name)

        render inertia: "Admin/Generic/Index", props: {
          title: t("mcweb.admin.minecraft.servers"),
          columns: [
            admin_column(:name, t("mcweb.admin.minecraft.col_name"), link: true),
            admin_column(:address, t("mcweb.admin.minecraft.col_address")),
            admin_column(:port, t("mcweb.admin.minecraft.col_port")),
            admin_column(:status, t("mcweb.admin.minecraft.col_status"))
          ],
          rows: servers.map do |server|
            admin_row(
              name: server.name,
              address: server.address.to_s,
              port: server.port.to_s,
              status: server_status_label(server.status),
              url: admin_minecraft_server_path(server)
            )
          end,
          actions: [ { label: t("mcweb.admin.minecraft.new_server"), href: new_admin_minecraft_server_path } ]
        }
      end

      def show
        latest = @server.server_snapshots.order(created_at: :desc).first
        na = t("mcweb.labels.not_available")
        render inertia: "Admin/Generic/Show", props: {
          title: @server.name,
          fields: [
            { label: t("mcweb.admin.minecraft.field_address"), value: @server.address.to_s },
            { label: t("mcweb.admin.minecraft.field_port"), value: @server.port.to_s },
            { label: t("mcweb.admin.minecraft.field_status"), value: server_status_label(@server.status) },
            { label: t("mcweb.admin.minecraft.field_server_id"), value: @server.public_id },
            { label: t("mcweb.admin.minecraft.field_secret_fingerprint"), value: @server.connector_secret_fingerprint.presence || t("mcweb.admin.minecraft.secret_not_generated") },
            { label: t("mcweb.admin.minecraft.field_last_heartbeat"), value: @server.last_heartbeat_at ? l(@server.last_heartbeat_at, format: :long) : na },
            { label: t("mcweb.admin.minecraft.field_online_players"), value: latest ? "#{latest.online_players}/#{latest.max_players}" : na },
            { label: t("mcweb.admin.minecraft.field_tps"), value: latest&.tps&.to_s || na },
            { label: t("mcweb.admin.minecraft.field_version"), value: latest&.version || na }
          ],
          backUrl: admin_minecraft_servers_path,
          actions: [
            { label: t("mcweb.admin.minecraft.action_edit"), href: edit_admin_minecraft_server_path(@server) },
            { label: t("mcweb.admin.minecraft.action_rotate_secret"), href: rotate_secret_admin_minecraft_server_path(@server), method: "post", confirm: t("mcweb.admin.minecraft.confirm_rotate_secret") },
            { label: t("mcweb.admin.minecraft.action_delete"), href: admin_minecraft_server_path(@server), method: "delete", confirm: t("mcweb.admin.minecraft.confirm_delete_server") }
          ]
        }
      end

      def rotate_secret
        secret = @server.generate_connector_secret!
        redirect_to admin_minecraft_server_path(@server), notice: t("mcweb.flash.connector_secret_generated", secret: secret)
      end

      def new
        render inertia: "Admin/Minecraft/Servers/Form", props: form_props(::Minecraft::Server.new(status: :offline, port: 25565))
      end

      def create
        @server = ::Minecraft::Server.new(server_params)

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
        if @server.update(server_params)
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

      def server_params
        params.expect(server: %i[name address port status])[:server]
      end

      def form_props(server)
        {
          title: server.persisted? ? t("mcweb.admin.minecraft.edit_server") : t("mcweb.admin.minecraft.new_server"),
          server: {
            name: server.name.to_s,
            address: server.address.to_s,
            port: server.port || 25565,
            status: server.status || "offline"
          },
          statusOptions: ::Minecraft::Server.statuses.keys.map { |s| { value: s, label: server_status_label(s) } },
          submitUrl: server.persisted? ? admin_minecraft_server_path(server) : admin_minecraft_servers_path,
          method: server.persisted? ? "patch" : "post",
          backUrl: admin_minecraft_servers_path
        }
      end

      def server_status_label(status)
        key = "mcweb.admin.minecraft.status_#{status}"
        I18n.exists?(key) ? t(key) : status.to_s
      end
    end
  end
end
