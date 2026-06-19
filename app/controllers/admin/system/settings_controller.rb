# frozen_string_literal: true

module Admin
  module System
    class SettingsController < BaseController
      before_action -> { require_permission("system.settings.manage") }

      def show
        settings = SiteSetting.order(:key)

        render inertia: "Admin/System/Settings/Show", props: {
          settings: settings.map do |setting|
            {
              key: setting.key,
              value: setting.value.is_a?(String) ? setting.value : setting.value.to_json
            }
          end
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

      def settings_params
        allowed_keys = SiteSetting.pluck(:key)
        params.fetch(:settings, {}).permit(*allowed_keys).to_h
      end
    end
  end
end
