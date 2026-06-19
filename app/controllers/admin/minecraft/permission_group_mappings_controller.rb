# frozen_string_literal: true

module Admin
  module Minecraft
    class PermissionGroupMappingsController < BaseController
      before_action -> { require_permission("minecraft.servers.manage") }
      before_action -> { require_admin_module!("minecraft") }

      SETTING_KEY = "minecraft.permission_group_mappings"

      def index
        mappings = current_mappings
        roles = Role.order(:name).pluck(:key, :name).map { |key, name| { key: key, name: name } }
        badges = Community::Badge.order(:name).pluck(:slug, :name).map { |slug, name| { slug: slug, name: name } }

        render inertia: "Admin/Minecraft/PermissionGroupMappings/Show", props: {
          mappings: mappings,
          roles: roles,
          badges: badges,
          createUrl: admin_minecraft_permission_group_mappings_path,
          backUrl: admin_minecraft_servers_path
        }
      end

      def create
        mappings = current_mappings
        mappings << {
          "game_group" => params[:game_group].to_s,
          "role_key" => params[:role_key].to_s.presence,
          "badge_slug" => params[:badge_slug].to_s.presence
        }.compact
        SiteSetting.set(SETTING_KEY, mappings.to_json)
        redirect_to admin_minecraft_permission_group_mappings_path, notice: t("mcweb.flash.mapping_added")
      end

      def update
        mappings = current_mappings
        index = params[:id].to_i
        mappings[index] = {
          "game_group" => params[:game_group].to_s,
          "role_key" => params[:role_key].to_s.presence,
          "badge_slug" => params[:badge_slug].to_s.presence
        }.compact
        SiteSetting.set(SETTING_KEY, mappings.to_json)
        redirect_to admin_minecraft_permission_group_mappings_path, notice: t("mcweb.flash.mapping_updated")
      end

      def destroy
        mappings = current_mappings
        mappings.delete_at(params[:id].to_i)
        SiteSetting.set(SETTING_KEY, mappings.to_json)
        redirect_to admin_minecraft_permission_group_mappings_path, notice: t("mcweb.flash.mapping_deleted")
      end

      private

      def current_mappings
        JSON.parse(SiteSetting.get(SETTING_KEY, "[]"))
      rescue JSON::ParserError
        []
      end
    end
  end
end
