# frozen_string_literal: true

require "json"
require "mcweb/plugins/registry"
require "mcweb/plugins/settings_store"

module Admin
  module System
    class PluginSettingsController < BaseController
      PERMISSION_KEY = "system.plugins.settings.manage"

      before_action -> { require_permission(PERMISSION_KEY) }
      before_action :disable_caching

      def show
        render_page
      end

      def update
        entry = selected_entry!
        values = submitted_values(entry.fetch(:schema))
        store_for(entry).update(
          values: values,
          unset_keys: submitted_unset_keys,
          expected_revision: required_expected_revision,
          actor: current_user,
          audit: audit_context
        )
        redirect_to settings_path(entry.fetch(:plugin_id)),
          notice: t("mcweb.admin.system.plugin_settings.updated")
      rescue Mcweb::Plugins::SettingValidationError => e
        render_page(
          selected_plugin_id: params[:plugin_id],
          form_values: safe_form_values(values, entry&.fetch(:schema, nil)),
          form_errors: serialized_errors(e.errors),
          page_error: translated_error(e.code),
          status: :unprocessable_entity
        )
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        render_page(
          selected_plugin_id: params[:plugin_id],
          page_error: translated_error("write_failed"),
          status: :unprocessable_entity
        )
      end

      def migrate
        entry = selected_entry!
        store_for(entry).migrate(
          expected_revision: required_expected_revision,
          actor: current_user,
          audit: audit_context
        )
        redirect_to settings_path(entry.fetch(:plugin_id)),
          notice: t("mcweb.admin.system.plugin_settings.migrated")
      rescue Mcweb::Plugins::SettingValidationError => e
        render_page(
          selected_plugin_id: params[:plugin_id],
          page_error: translated_error(e.code),
          status: :unprocessable_entity
        )
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        render_page(
          selected_plugin_id: params[:plugin_id],
          page_error: translated_error("write_failed"),
          status: :unprocessable_entity
        )
      end

      def rollback
        entry = selected_entry!
        store_for(entry).rollback(
          revision: params[:revision],
          expected_revision: required_expected_revision,
          actor: current_user,
          audit: audit_context
        )
        redirect_to settings_path(entry.fetch(:plugin_id)),
          notice: t("mcweb.admin.system.plugin_settings.rolled_back")
      rescue Mcweb::Plugins::SettingValidationError => e
        render_page(
          selected_plugin_id: params[:plugin_id],
          page_error: translated_error(e.code),
          status: :unprocessable_entity
        )
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        render_page(
          selected_plugin_id: params[:plugin_id],
          page_error: translated_error("write_failed"),
          status: :unprocessable_entity
        )
      end

      private

      def render_page(
        selected_plugin_id: params[:plugin_id],
        form_values: nil,
        form_errors: {},
        page_error: nil,
        status: :ok
      )
        catalog = Mcweb::Plugins.settings_catalog
        entry = select_entry(catalog, selected_plugin_id)
        selected = entry && serialize_selected(
          entry,
          form_values:,
          form_errors:,
          page_error:
        )

        render inertia: "Admin/System/PluginSettings/Show",
          props: {
            title: t("mcweb.admin.system.plugin_settings.title"),
            catalog: catalog.map { |item| serialize_catalog_entry(item) },
            selected:,
            actions: action_paths
          },
          status:
      rescue Mcweb::Plugins::SettingValidationError => e
        render inertia: "Admin/System/PluginSettings/Show",
          props: {
            title: t("mcweb.admin.system.plugin_settings.title"),
            catalog: Mcweb::Plugins.settings_catalog.map { |item| serialize_catalog_entry(item) },
            selected: entry && serialize_unreadable_entry(entry, translated_error(e.code)),
            actions: action_paths
          },
          status: :unprocessable_entity
      end

      def serialize_selected(entry, form_values:, form_errors:, page_error:)
        schema = entry.fetch(:schema)
        store = store_for(entry)
        snapshot = store.snapshot
        values = snapshot.values.merge(safe_form_values(form_values, schema))
        {
          plugin_id: entry.fetch(:plugin_id),
          plugin_name: entry.fetch(:plugin_name),
          plugin_version: entry.fetch(:plugin_version),
          status: entry.fetch(:status),
          schema_version: schema.version,
          schema_digest: schema.digest,
          revision: snapshot.revision,
          complete: snapshot.complete,
          migration_available: snapshot.migration_available,
          persisted_at: snapshot.persisted_at,
          page_error:,
          groups: serialize_groups(schema, values, form_errors),
          history: store.history
        }
      end

      def serialize_groups(schema, values, form_errors)
        schema.groups.values
          .sort_by { |group| [ group.fetch("position"), group.fetch("key") ] }
          .map do |group|
            fields = schema.properties.values
              .select { |property| property.group == group.fetch("key") }
              .sort_by(&:key)
              .map { |property| serialize_field(property, values, form_errors) }
            {
              key: group.fetch("key"),
              title: phrase(group.fetch("title_phrase")),
              description: phrase(group["description_phrase"]),
              fields:
            }
          end
      end

      def serialize_field(property, values, form_errors)
        {
          key: property.key,
          type: property.type,
          input: property.input,
          required: property.to_h.fetch("required"),
          sensitive: property.sensitive?,
          configured: values.key?(property.key),
          value: property.sensitive? ? nil : values[property.key],
          label: phrase(property.title_phrase),
          description: phrase(property.description_phrase),
          placeholder: phrase(property.placeholder_phrase),
          enum: property.enum&.map do |value|
            {
              value:,
              label: phrase(property.enum_phrases[enum_key(value)]) || value.to_s
            }
          end,
          minimum: property.minimum,
          maximum: property.maximum,
          min_length: property.min_length,
          max_length: property.max_length,
          error: form_errors[property.key]
        }
      end

      def serialize_catalog_entry(entry)
        schema = entry.fetch(:schema)
        {
          plugin_id: entry.fetch(:plugin_id),
          plugin_name: entry.fetch(:plugin_name),
          plugin_version: entry.fetch(:plugin_version),
          status: entry.fetch(:status),
          schema_version: schema.version
        }
      end

      def serialize_unreadable_entry(entry, error)
        schema = entry.fetch(:schema)
        {
          plugin_id: entry.fetch(:plugin_id),
          plugin_name: entry.fetch(:plugin_name),
          plugin_version: entry.fetch(:plugin_version),
          status: entry.fetch(:status),
          schema_version: schema.version,
          schema_digest: schema.digest,
          revision: 0,
          complete: false,
          migration_available: false,
          page_error: error,
          persisted_at: nil,
          groups: [],
          history: []
        }
      end

      def select_entry(catalog, plugin_id)
        requested = plugin_id.to_s
        return catalog.first if requested.blank?

        catalog.find { |entry| entry.fetch(:plugin_id) == requested }
      end

      def selected_entry!
        select_entry(Mcweb::Plugins.settings_catalog, params[:plugin_id]) ||
          raise(
            Mcweb::Plugins::SettingValidationError.new(
              code: "plugin_not_found",
              message: "plugin settings schema is not available"
            )
          )
      end

      def store_for(entry)
        Mcweb::Plugins::SettingsStore.new(
          plugin_id: entry.fetch(:plugin_id),
          schema: entry.fetch(:schema)
        )
      end

      def submitted_values(schema)
        source = params[:values]
        values = if source.nil?
          {}
        elsif source.respond_to?(:to_unsafe_h)
          source.to_unsafe_h
        elsif source.is_a?(Hash)
          source
        else
          raise Mcweb::Plugins::SettingValidationError.new(
            code: "validation_failed",
            message: "settings values must be a mapping"
          )
        end
        schema.sensitive_keys.each do |key|
          values.delete(key) if values[key].blank?
        end
        values
      end

      def submitted_unset_keys
        value = params[:unset_keys]
        return [] if value.nil?

        value
      end

      def required_expected_revision
        value = params[:expected_revision]
        if value.nil?
          raise Mcweb::Plugins::SettingValidationError.new(
            code: "invalid_argument",
            message: "expected revision is required"
          )
        end
        value
      end

      def safe_form_values(values, schema)
        return {} unless values.respond_to?(:to_h) && schema

        values.to_h.each_with_object({}) do |(key, value), safe|
          property = schema.properties[key.to_s]
          safe[key.to_s] = value if property && !property.sensitive?
        end
      end

      def serialized_errors(errors)
        errors.to_h.transform_values { |messages| Array(messages).join(" ") }
      end

      def phrase(key)
        return if key.blank?

        I18n.exists?(key, I18n.locale) ? I18n.t(key, locale: I18n.locale) : key
      end

      def enum_key(value)
        value.is_a?(String) ? value : JSON.generate(value)
      end

      def settings_path(plugin_id)
        admin_system_plugin_settings_path(plugin_id:)
      end

      def translated_error(code)
        key = "mcweb.admin.system.plugin_settings.errors.#{code}"
        return t(key) if I18n.exists?(key, I18n.locale)

        t("mcweb.admin.system.plugin_settings.errors.generic")
      end

      def action_paths
        {
          show: admin_system_plugin_settings_path,
          update: admin_system_plugin_settings_path,
          migrate: migrate_admin_system_plugin_settings_path,
          rollback: rollback_admin_system_plugin_settings_path
        }
      end

      def audit_context
        {
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        }
      end

      def disable_caching
        response.set_header("Cache-Control", "no-store")
      end
    end
  end
end
