# frozen_string_literal: true

require "uri"

module Admin
  module System
    class SettingsController < BaseController
      BASIC_SETTING_KEYS = %w[
        general.site_name
        site.name
        site.url
      ].freeze
      MAX_SITE_NAME_LENGTH = 80

      SECTION_DEFINITIONS = [
        {
          id: "experience",
          entries: [
            {
              id: "feature_toggles",
              kind: "configuration",
              route: :admin_system_feature_toggles_path,
              permission: "system.settings.manage"
            },
            {
              id: "forum",
              kind: "configuration",
              route: :admin_forum_settings_path,
              permission: "system.settings.manage"
            },
            {
              id: "store",
              kind: "configuration",
              route: :admin_store_settings_path,
              permission: "system.settings.manage"
            },
            {
              id: "minecraft",
              kind: "configuration",
              route: :admin_minecraft_settings_path,
              permission: "minecraft.servers.manage",
              admin_module: "minecraft"
            }
          ]
        },
        {
          id: "security",
          entries: [
            {
              id: "rate_limits",
              kind: "security",
              route: :admin_system_rate_limits_path,
              permission: "system.settings.manage"
            },
            {
              id: "api_keys",
              kind: "security",
              route: :admin_system_api_keys_path,
              permission: "system.settings.manage"
            },
            {
              id: "webhook_subscriptions",
              kind: "security",
              route: :admin_system_webhook_subscriptions_path,
              permission: "system.settings.manage"
            }
          ]
        },
        {
          id: "extensions",
          entries: [
            {
              id: "applications",
              kind: "extension",
              route: :admin_system_applications_path,
              permission: "system.settings.manage"
            },
            {
              id: "plugin_settings",
              kind: "extension",
              route: :admin_system_plugin_settings_path,
              permission: "system.plugins.settings.manage"
            }
          ]
        },
        {
          id: "operations",
          entries: [
            {
              id: "jobs",
              kind: "operations",
              route: :admin_system_jobs_path,
              permission: "system.jobs.read"
            },
            {
              id: "health_overview",
              kind: "operations",
              route: :admin_root_path
            }
          ]
        }
      ].freeze

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
        render_page
      end

      def update
        if params.key?(:basic_settings)
          update_basic_settings
        else
          update_system_settings
        end
      end

      private

      def update_basic_settings
        values = normalized_basic_settings
        errors = basic_settings_errors(values)
        if errors.any?
          render_page(
            basic_settings: values,
            form_errors: errors,
            status: :unprocessable_entity
          )
          return
        end

        updates = {
          "general.site_name" => values.fetch(:site_name),
          "site.name" => values.fetch(:site_name),
          "site.url" => values.fetch(:site_url)
        }
        before_state = BASIC_SETTING_KEYS.index_with { |key| SiteSetting.get(key) }
        changed_keys = updates.keys.select do |key|
          before_state[key].to_s != updates.fetch(key).to_s
        end

        SiteSetting.transaction do
          changed_keys.each { |key| SiteSetting.set(key, updates.fetch(key)) }
          audit_basic_settings_update(
            changed_keys: changed_keys,
            before_state: before_state,
            after_state: before_state.merge(updates.slice(*changed_keys))
          ) if changed_keys.any?
        end

        redirect_to admin_system_settings_path,
          notice: t("mcweb.flash.system_settings_saved")
      end

      def update_system_settings
        protected_keys = submitted_protected_setting_keys
        if protected_keys.any?
          reject_protected_setting_update(protected_keys)
          return
        end

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

        redirect_to admin_system_settings_path,
          notice: t("mcweb.flash.system_settings_saved")
      end

      def render_page(
        basic_settings: basic_settings_props,
        form_errors: {},
        status: :ok
      )
        render inertia: "Admin/System/Settings/Show", props: {
          sections: settings_sections,
          basicSettings: basic_settings,
          formErrors: form_errors,
          updateUrl: admin_system_settings_path,
          settings: system_settings_props
        }, status: status
      end

      def system_settings_props
        label_maps = translation_maps("labels")
        hint_maps = translation_maps("hints")

        SiteSetting.where.not(key: BASIC_SETTING_KEYS).order(:key).filter_map do |setting|
          next if Mcweb::SettingsNamespaceRegistry.protected?(setting.key)

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
      end

      def basic_settings_props
        {
          site_name: SiteSetting.get("general.site_name").presence ||
            SiteSetting.get("site.name").presence ||
            "McWeb",
          site_url: SiteSetting.get("site.url", "").to_s
        }
      end

      def normalized_basic_settings
        submitted = params.require(:basic_settings).permit(:site_name, :site_url)
        {
          site_name: submitted[:site_name].to_s.strip,
          site_url: normalize_site_url(submitted[:site_url])
        }
      end

      def normalize_site_url(value)
        value.to_s.strip.sub(%r{/+\z}, "")
      end

      def basic_settings_errors(values)
        errors = {}
        name = values.fetch(:site_name)
        url = values.fetch(:site_url)
        errors[:site_name] = "required" if name.blank?
        if name.length > MAX_SITE_NAME_LENGTH
          errors[:site_name] = "name_too_long"
        elsif name.match?(/[[:cntrl:]]/)
          errors[:site_name] = "name_invalid"
        end
        errors[:site_url] = "url_invalid" unless valid_site_url?(url)
        errors
      end

      def valid_site_url?(value)
        return true if value.blank?

        uri = URI.parse(value)
        uri.is_a?(URI::HTTP) &&
          uri.host.present? &&
          uri.userinfo.blank? &&
          uri.query.nil? &&
          uri.fragment.nil? &&
          (uri.path.blank? || uri.path == "/")
      rescue URI::InvalidURIError
        false
      end

      def audit_basic_settings_update(changed_keys:, before_state:, after_state:)
        Administration::AuditLogger.call(
          actor: current_user,
          action: "admin.settings_updated",
          metadata: { keys: changed_keys },
          before_state: before_state.slice(*changed_keys),
          after_state: after_state.slice(*changed_keys),
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )
      end

      def settings_sections
        SECTION_DEFINITIONS.filter_map do |section|
          entries = section.fetch(:entries).filter_map do |entry|
            next unless visible_entry?(entry)

            {
              id: entry.fetch(:id),
              kind: entry.fetch(:kind),
              url: public_send(entry.fetch(:route))
            }
          end
          next if entries.empty?

          { id: section.fetch(:id), entries: entries }
        end
      end

      def visible_entry?(entry)
        permission = entry[:permission]
        return false if permission && !current_user.permission?(permission)

        admin_module = entry[:admin_module]
        return false if admin_module && !current_user.admin_module_allowed?(admin_module)

        true
      end

      def settings_params
        allowed_keys = SiteSetting.where.not(key: BASIC_SETTING_KEYS).pluck(:key).reject do |key|
          Mcweb::SettingsNamespaceRegistry.protected?(key)
        end
        params.fetch(:settings, {}).permit(*allowed_keys).to_h
      end

      def submitted_protected_setting_keys
        submitted = params[:settings]
        return [] unless submitted.respond_to?(:keys)

        submitted.keys
          .map(&:to_s)
          .select { |key| Mcweb::SettingsNamespaceRegistry.protected?(key) }
          .uniq
          .sort
      end

      def reject_protected_setting_update(keys)
        owners = keys.index_with do |key|
          Mcweb::SettingsNamespaceRegistry.owner_for(key)
        end
        Administration::AuditLogger.call(
          actor: current_user,
          action: "admin.settings_protected_write_rejected",
          metadata: { keys:, owners: },
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )

        redirect_to admin_system_settings_path,
          alert: t("mcweb.admin.system.settings.protected_namespace")
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
