# frozen_string_literal: true

require_relative "result"
require_relative "../../plugins/setting_schema"
require_relative "../../plugins/settings_store"

module Mcweb
  module PluginApi
    module V1
      class Settings
        READ_CAPABILITY = "plugin.settings.read"
        WRITE_CAPABILITY = "plugin.settings.write"

        attr_reader :declaration

        def initialize(manifest:, capability_auditor: nil)
          @capability_auditor = capability_auditor
          @declaration = Mcweb::Plugins::SettingSchemaLoader.load(manifest)
          @store = if @declaration
            Mcweb::Plugins::SettingsStore.new(
              plugin_id: manifest.id,
              schema: @declaration
            )
          end
          freeze
        end

        def descriptor
          audit(READ_CAPABILITY)
          return schema_missing_result unless declaration

          Result.success(declaration.to_h)
        rescue StandardError => e
          safe_failure(e)
        end

        def values
          audit(READ_CAPABILITY)
          return schema_missing_result unless declaration

          snapshot = @store.snapshot
          return migration_required_result if snapshot.migration_available

          Result.success(snapshot.to_h)
        rescue Mcweb::Plugins::SettingValidationError => e
          validation_failure(e)
        rescue StandardError => e
          safe_failure(e)
        end

        def get(key, default: nil)
          audit(READ_CAPABILITY)
          return schema_missing_result unless declaration

          normalized_key = key.to_s
          unless declaration.properties.key?(normalized_key)
            return Result.failure(
              code: "setting_not_declared",
              error: "plugin setting is not declared"
            )
          end

          snapshot = @store.snapshot
          return migration_required_result if snapshot.migration_available

          Result.success(snapshot.values.fetch(normalized_key, default))
        rescue Mcweb::Plugins::SettingValidationError => e
          validation_failure(e)
        rescue StandardError => e
          safe_failure(e)
        end

        def update(values:, unset_keys: [], expected_revision: nil)
          audit(WRITE_CAPABILITY)
          return schema_missing_result unless declaration

          snapshot = @store.update(
            values:,
            unset_keys:,
            expected_revision:
          )
          Result.success(snapshot.to_h)
        rescue Mcweb::Plugins::SettingValidationError => e
          validation_failure(e)
        rescue StandardError => e
          safe_failure(e)
        end

        def migrate(expected_revision: nil)
          audit(WRITE_CAPABILITY)
          return schema_missing_result unless declaration

          Result.success(@store.migrate(expected_revision:).to_h)
        rescue Mcweb::Plugins::SettingValidationError => e
          validation_failure(e)
        rescue StandardError => e
          safe_failure(e)
        end

        def rollback(revision:, expected_revision: nil)
          audit(WRITE_CAPABILITY)
          return schema_missing_result unless declaration

          Result.success(
            @store.rollback(
              revision:,
              expected_revision:
            ).to_h
          )
        rescue Mcweb::Plugins::SettingValidationError => e
          validation_failure(e)
        rescue StandardError => e
          safe_failure(e)
        end

        private

        def schema_missing_result
          Result.failure(
            code: "settings_not_declared",
            error: "plugin does not declare a settings schema"
          )
        end

        def migration_required_result
          Result.failure(
            code: "migration_required",
            error: "plugin settings must be migrated into the current schema version"
          )
        end

        def validation_failure(error)
          Result.failure(
            code: error.code,
            error: error.message,
            errors: error.errors
          )
        end

        def safe_failure(error)
          Result.failure(
            code: "host_error",
            error: "#{error.class}: plugin settings operation failed"
          )
        end

        def audit(capability)
          @capability_auditor&.call(capability)
        end
      end
    end
  end
end
