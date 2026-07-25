# frozen_string_literal: true

module Admin
  module System
    class SettingsController < BaseController
      before_action -> { require_permission("system.settings.manage") }

      TRANSLATION_SCOPES = %w[
        mcweb.admin.system.settings
        mcweb.admin.forum.settings
        mcweb.admin.forum.points
        mcweb.admin.store.settings
      ].freeze
      SENSITIVE_KEY_PATTERN = /(?:^|[._-])(secret|password|token|private_key)(?:$|[._-])/i
      READ_ONLY_SETTING_KEYS = %w[
        forum.online_peak_at
        forum.online_peak_count
        webhook.failure_alert_last_sent_at
      ].freeze

      def show
        settings = SiteSetting.order(:key)
        label_maps = translation_maps("labels")
        hint_maps = translation_maps("hints")

        render inertia: "Admin/System/Settings/Show", props: {
          settings: settings.map do |setting|
            sensitive = sensitive_key?(setting.key)
            {
              key: setting.key,
              value: sensitive ? "" : serialized_value(setting.value),
              label: translated_setting_value(setting.key, label_maps) ||
                t("mcweb.admin.system.settings.custom_label"),
              hint: translated_setting_value(setting.key, hint_maps),
              sensitive: sensitive,
              configured: sensitive && setting.value.present?
            }
          end
        }
      end

      def update
        updates = settings_params.except(*READ_ONLY_SETTING_KEYS)
        updates.reject! { |key, value| sensitive_key?(key) && value.blank? }

        feature_updates = feature_flag_updates(updates)
        if feature_updates.any?
          result = FeatureFlags.update_from_params!(feature_updates)
          unless result.success?
            redirect_to admin_system_settings_path,
                        alert: t("mcweb.admin.system.settings.portal_required")
            return
          end
        end

        updates.except(*feature_setting_keys).each do |key, value|
          # Sensitive fields are deliberately never sent back to the browser.
          # Leaving one blank therefore means "keep the current secret".
          SiteSetting.set(key, value)
        end

        if updates.any?
          Administration::AuditLogger.call(
            actor: current_user,
            action: "admin.settings_updated",
            metadata: { keys: updates.keys }
          )
        end

        redirect_to admin_system_settings_path, notice: t("mcweb.flash.system_settings_saved")
      end

      private

      def settings_params
        allowed_keys = SiteSetting.pluck(:key)
        params.fetch(:settings, {}).permit(*allowed_keys).to_h
      end

      def translation_maps(kind)
        TRANSLATION_SCOPES.filter_map do |scope|
          translations = I18n.t("#{scope}.#{kind}", default: {})
          translations if translations.is_a?(Hash)
        end
      end

      def translated_setting_value(key, maps)
        maps.each do |translations|
          value = translations[key.to_sym] || translations[key]
          return value if value.present?
        end

        nil
      end

      def sensitive_key?(key)
        key.match?(SENSITIVE_KEY_PATTERN)
      end

      def serialized_value(value)
        value.is_a?(String) ? value : value.to_json
      end

      def feature_flag_updates(updates)
        FeatureFlags.definitions.each_with_object({}) do |definition, values|
          next unless updates.key?(definition.key)

          values[definition.id.to_s] = updates[definition.key]
        end
      end

      def feature_setting_keys
        @feature_setting_keys ||= FeatureFlags.definitions.map(&:key)
      end
    end
  end
end
