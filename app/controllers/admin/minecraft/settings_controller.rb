# frozen_string_literal: true

module Admin
  module Minecraft
    class SettingsController < BaseController
      before_action -> { require_permission("minecraft.servers.manage") }
      before_action -> { require_admin_module!("minecraft") }

      def show
        render inertia: "Admin/Minecraft/Settings/Show", props: {
          settings: {
            link_command: SiteSetting.get("minecraft.link_command", "/website link"),
            skin_mode: SiteSetting.get("minecraft.profile.skin_mode", "2d"),
            bridges_enabled: SiteSetting.get("minecraft.bridges.enabled", "placeholderapi,luckperms,vault"),
            bridge_placeholders: SiteSetting.get("minecraft.bridges.placeholders", ""),
            profile_sections: SiteSetting.get("minecraft.profile.sections", "minecraft,trust,roles,game_groups")
          },
          updateUrl: admin_minecraft_settings_path
        }
      end

      def update
        SiteSetting.set("minecraft.link_command", params[:link_command]) if params[:link_command]
        SiteSetting.set("minecraft.profile.skin_mode", params[:skin_mode]) if params[:skin_mode]
        SiteSetting.set("minecraft.bridges.enabled", params[:bridges_enabled]) if params[:bridges_enabled]
        SiteSetting.set("minecraft.bridges.placeholders", params[:bridge_placeholders]) if params.key?(:bridge_placeholders)
        SiteSetting.set("minecraft.profile.sections", params[:profile_sections]) if params[:profile_sections]

        redirect_to admin_minecraft_settings_path, notice: t("mcweb.flash.minecraft_settings_saved")
      end
    end
  end
end
