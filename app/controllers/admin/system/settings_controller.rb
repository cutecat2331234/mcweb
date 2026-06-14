# frozen_string_literal: true

module Admin
  module System
    class SettingsController < BaseController
      before_action -> { require_permission("admin.system.settings") }

      def show
        @settings = SiteSetting.order(:key)
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

        redirect_to admin_system_settings_path, notice: "Settings updated."
      end

      private

      def settings_params
        params.fetch(:settings, {}).permit!.to_h
      end
    end
  end
end
