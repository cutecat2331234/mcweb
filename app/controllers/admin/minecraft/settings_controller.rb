# frozen_string_literal: true

module Admin
  module Minecraft
    class SettingsController < BaseController
      before_action -> { require_permission("minecraft.servers.manage") }
      def show
        render inertia: "Admin/Minecraft/Settings/Show", props: {
          settings: {
            link_command: SiteSetting.get("minecraft.link_command", "/website link"),
            skin_mode: SiteSetting.get("minecraft.profile.skin_mode", "2d"),
            bridges_enabled: SiteSetting.get("minecraft.bridges.enabled", "placeholderapi,luckperms,vault"),
            bridge_placeholders: SiteSetting.get("minecraft.bridges.placeholders", ""),
            profile_sections: SiteSetting.get("minecraft.profile.sections", "minecraft,trust,roles,game_groups"),
            graceful_stop_enabled: SiteSetting.get("minecraft.graceful_stop.enabled", "true"),
            graceful_stop_countdown: SiteSetting.get("minecraft.graceful_stop.countdown_seconds", "30"),
            graceful_stop_message: SiteSetting.get("minecraft.graceful_stop.message", "Server shutting down in {seconds} seconds"),
            graceful_stop_commands: SiteSetting.get("minecraft.graceful_stop.commands", "save-all,stop"),
            exec_command_allowed_prefixes: SiteSetting.get("minecraft.exec_command.allowed_prefixes", ""),
            pause_fulfill_during_maintenance: SiteSetting.get("minecraft.commerce.pause_fulfill_during_maintenance", "true"),
            backup_enabled: SiteSetting.get("minecraft.backup.enabled", "false"),
            backup_schedule: SiteSetting.get("minecraft.backup.schedule", "0 3 * * *")
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
        SiteSetting.set("minecraft.graceful_stop.enabled", params[:graceful_stop_enabled]) if params.key?(:graceful_stop_enabled)
        SiteSetting.set("minecraft.graceful_stop.countdown_seconds", params[:graceful_stop_countdown]) if params[:graceful_stop_countdown]
        SiteSetting.set("minecraft.graceful_stop.message", params[:graceful_stop_message]) if params[:graceful_stop_message]
        SiteSetting.set("minecraft.graceful_stop.commands", params[:graceful_stop_commands]) if params[:graceful_stop_commands]
        SiteSetting.set("minecraft.exec_command.allowed_prefixes", params[:exec_command_allowed_prefixes]) if params.key?(:exec_command_allowed_prefixes)
        SiteSetting.set("minecraft.commerce.pause_fulfill_during_maintenance", params[:pause_fulfill_during_maintenance]) if params.key?(:pause_fulfill_during_maintenance)
        SiteSetting.set("minecraft.backup.enabled", params[:backup_enabled]) if params.key?(:backup_enabled)
        SiteSetting.set("minecraft.backup.schedule", params[:backup_schedule]) if params[:backup_schedule]

        redirect_to admin_minecraft_settings_path, notice: t("mcweb.flash.minecraft_settings_saved")
      end
    end
  end
end
