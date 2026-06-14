# frozen_string_literal: true

module Admin
  module Minecraft
    class ServersController < BaseController
      before_action -> { require_permission("minecraft.servers.manage") }
      before_action :set_server, only: %i[show edit update destroy]

      def index
        servers = ::Minecraft::Server.order(:name)

        render inertia: "Admin/Generic/Index", props: {
          title: "Minecraft 服务器",
          columns: [
            admin_column(:name, "名称", link: true),
            admin_column(:host, "主机"),
            admin_column(:port, "端口"),
            admin_column(:status, "状态")
          ],
          rows: servers.map do |server|
            admin_row(
              name: server.name,
              host: server.host,
              port: server.port.to_s,
              status: server.status,
              url: admin_minecraft_server_path(server)
            )
          end
        }
      end

      def show
        render inertia: "Admin/Generic/Show", props: {
          title: @server.name,
          fields: [
            { label: "主机", value: @server.host },
            { label: "端口", value: @server.port.to_s },
            { label: "状态", value: @server.status }
          ],
          backUrl: admin_minecraft_servers_path
        }
      end

      def new
        @server = ::Minecraft::Server.new
      end

      def create
        @server = ::Minecraft::Server.new(server_params)

        if @server.save
          redirect_to admin_minecraft_server_path(@server), notice: "Server created."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        if @server.update(server_params)
          redirect_to admin_minecraft_server_path(@server), notice: "Server updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @server.destroy!
        redirect_to admin_minecraft_servers_path, notice: "Server deleted."
      end

      private

      def set_server
        @server = ::Minecraft::Server.find_by!(public_id: params[:id])
      end

      def server_params
        params.expect(server: %i[name host port status])[:server]
      end
    end
  end
end
