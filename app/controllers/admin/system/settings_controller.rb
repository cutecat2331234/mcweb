# frozen_string_literal: true

module Admin
  module System
    class SettingsController < BaseController
      before_action -> { require_permission("system.settings.manage") }

      BOOLEAN_ZERO_ONE_KEYS = %w[
        forum.auto_close_on_solved
        forum.group_pm_creator_only_add
        minecraft.backup.enabled
        minecraft.commerce.pause_fulfill_during_maintenance
        minecraft.graceful_stop.enabled
      ].freeze

      def show
        settings = SiteSetting.order(:key)

        render inertia: "Admin/System/Settings/Show", props: {
          settings: settings.map { |setting| setting_props(setting) }
        }
      end

      def update
        settings_params.each do |key, value|
          SiteSetting.set(key, value)
        end

        Administration::AuditLogger.call(
          actor: current_user,
          action: "admin.settings_updated",
          metadata: { keys: settings_params.keys }
        )

        redirect_to admin_system_settings_path, notice: t("mcweb.flash.system_settings_saved")
      end

      private

      def setting_props(setting)
        value = setting.value.is_a?(String) ? setting.value : setting.value.to_json
        boolean = boolean_setting?(setting.key, value)
        one_zero = boolean && value.in?(%w[0 1])

        {
          key: setting.key,
          value: value,
          control: boolean ? "boolean" : "text",
          enabled_value: one_zero ? "1" : "true",
          disabled_value: one_zero ? "0" : "false"
        }
      end

      def boolean_setting?(key, value)
        return true if value.in?(%w[true false])
        return false unless value.in?(%w[0 1])

        BOOLEAN_ZERO_ONE_KEYS.include?(key) ||
          key.start_with?("store.features.") ||
          key.match?(/\Aforum\..+_enabled\z/)
      end

      def settings_params
        allowed_keys = SiteSetting.pluck(:key)
        params.fetch(:settings, {}).permit(*allowed_keys).to_h
      end
    end
  end
end
