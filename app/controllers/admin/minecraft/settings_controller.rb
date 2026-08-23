# frozen_string_literal: true

module Admin
  module Minecraft
    class SettingsController < BaseController
      include RegisteredSiteSettingUpdates

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
            backup_schedule: SiteSetting.get("minecraft.backup.schedule", "0 3 * * *"),
            primary_account_switch_policy: ::Minecraft::PrimaryAccountPolicy.normalized_policy,
            primary_account_cooldown_seconds: ::Minecraft::PrimaryAccountPolicy.snapshot(
              user: current_user
            ).cooldown_seconds.to_s,
            primary_account_request_expiry_hours: ::Minecraft::PrimaryAccountPolicy.snapshot(
              user: current_user
            ).request_expiry_hours.to_s
          },
          updateUrl: admin_minecraft_settings_path
        }
      end

      def update
        primary_account_updates = primary_account_setting_updates
        return if primary_account_updates.nil?

        updates = normalize_registered_site_setting_updates(
          minecraft_settings_params.merge(primary_account_updates),
          owner: "admin.minecraft.settings"
        )
        SiteSetting.transaction do
          updates.each { |key, value| SiteSetting.set(key, value) }
        end
        if updates.any?
          Administration::AuditLogger.call(
            actor: current_user,
            action: "admin.minecraft_settings_updated",
            metadata: { keys: updates.keys }
          )
        end
        redirect_to admin_minecraft_settings_path, notice: t("mcweb.flash.minecraft_settings_saved")
      rescue Mcweb::SettingsNamespaceRegistry::ValidationError => error
        redirect_to admin_minecraft_settings_path,
          alert: registered_site_setting_error(error)
      end

      private

      SETTING_PARAM_MAP = {
        link_command: "minecraft.link_command",
        skin_mode: "minecraft.profile.skin_mode",
        bridges_enabled: "minecraft.bridges.enabled",
        bridge_placeholders: "minecraft.bridges.placeholders",
        profile_sections: "minecraft.profile.sections",
        graceful_stop_enabled: "minecraft.graceful_stop.enabled",
        graceful_stop_countdown: "minecraft.graceful_stop.countdown_seconds",
        graceful_stop_message: "minecraft.graceful_stop.message",
        graceful_stop_commands: "minecraft.graceful_stop.commands",
        exec_command_allowed_prefixes: "minecraft.exec_command.allowed_prefixes",
        pause_fulfill_during_maintenance: "minecraft.commerce.pause_fulfill_during_maintenance",
        backup_enabled: "minecraft.backup.enabled",
        backup_schedule: "minecraft.backup.schedule"
      }.freeze

      def minecraft_settings_params
        SETTING_PARAM_MAP.each_with_object({}) do |(param_key, setting_key), updates|
          next unless params.key?(param_key)

          updates[setting_key] = params[param_key]
        end
      end

      def primary_account_setting_updates
        updates = {}
        if params.key?(:primary_account_switch_policy)
          policy = params[:primary_account_switch_policy].to_s
          unless policy.in?(::Minecraft::PrimaryAccountPolicy::POLICIES)
            return reject_primary_account_settings
          end
          updates["minecraft.primary_account.switch_policy"] = policy
        end

        if params.key?(:primary_account_cooldown_seconds)
          seconds = bounded_integer(
            params[:primary_account_cooldown_seconds],
            minimum: 0,
            maximum: ::Minecraft::PrimaryAccountPolicy::MAX_COOLDOWN_SECONDS
          )
          return reject_primary_account_settings unless seconds

          updates["minecraft.primary_account.cooldown_seconds"] = seconds.to_s
        end

        if params.key?(:primary_account_request_expiry_hours)
          hours = bounded_integer(
            params[:primary_account_request_expiry_hours],
            minimum: 1,
            maximum: ::Minecraft::PrimaryAccountPolicy::MAX_REQUEST_EXPIRY_HOURS
          )
          return reject_primary_account_settings unless hours

          updates["minecraft.primary_account.request_expiry_hours"] = hours.to_s
        end

        updates
      end

      def reject_primary_account_settings
        redirect_to admin_minecraft_settings_path,
                    alert: t("mcweb.flash.primary_account_policy_invalid")
        nil
      end

      def bounded_integer(value, minimum:, maximum:)
        integer = Integer(value, exception: false)
        return unless integer&.between?(minimum, maximum)

        integer
      end
    end
  end
end
