# frozen_string_literal: true

module Admin
  module Minecraft
    class ServersController < BaseController
      before_action -> { require_permission("minecraft.servers.manage") }
      before_action :set_server, only: %i[show edit update destroy]

      def index
        @servers = ::Minecraft::Server.order(:name)
      end

      def show
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
