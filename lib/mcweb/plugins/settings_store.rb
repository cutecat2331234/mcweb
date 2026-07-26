# frozen_string_literal: true

require "digest"
require_relative "../events"
require_relative "setting_schema"

module Mcweb
  module Plugins
    class SettingsStore
      Snapshot = Data.define(
        :plugin_id,
        :schema_version,
        :schema_digest,
        :revision,
        :values,
        :complete,
        :migration_available,
        :persisted_at
      ) do
        def to_h
          {
            plugin_id:,
            schema_version:,
            schema_digest:,
            revision:,
            values:,
            complete:,
            migration_available:,
            persisted_at:
          }.freeze
        end
      end

      MAX_HISTORY = 100

      attr_reader :plugin_id, :schema

      def initialize(plugin_id:, schema:)
        @plugin_id = plugin_id.to_s.freeze
        @schema = schema
        unless schema.is_a?(SettingSchema) && schema.plugin_id == @plugin_id
          raise ArgumentError, "settings schema does not belong to the requested plugin"
        end
      end

      def snapshot
        record = current_record
        return snapshot_for(
          record,
          migration_available: pending_migration_source(record).present?
        ) if record

        snapshot_for(nil, migration_available: migration_source.present?)
      rescue Lockbox::DecryptionError
        raise unreadable_settings_error
      end

      def update(values:, unset_keys: [], expected_revision: nil, actor: nil, audit: {})
        changes = schema.validate_partial_values(values)
        normalized_unset = normalize_unset_keys(unset_keys)
        if (changes.keys & normalized_unset).any?
          raise SettingValidationError.new(
            code: "validation_failed",
            message: "a plugin setting cannot be updated and unset in the same request"
          )
        end

        mutate_with_lock do |current|
          if pending_migration_source(current).present?
            raise SettingValidationError.new(
              code: "migration_required",
              message: "plugin settings must be migrated before they can be changed"
            )
          end
          assert_expected_revision!(current, expected_revision)
          before_values = current ? read_values!(current) : schema.defaults.deep_dup
          after_values = before_values.merge(changes)
          normalized_unset.each { |key| after_values.delete(key) }
          after_values = schema.validate_values(after_values)
          next snapshot_for(current) if current && before_values == after_values

          record = append_version!(
            current:,
            values: after_values,
            change_kind: "update",
            actor:,
            audit:
          )
          snapshot_for(record)
        end
      rescue Lockbox::DecryptionError
        raise unreadable_settings_error
      end

      def migrate(expected_revision: nil, actor: nil, audit: {})
        mutate_with_lock do |current|
          assert_expected_revision!(current, expected_revision)
          source = pending_migration_source(current)
          next snapshot_for(current) if current && source.nil?
          unless source
            raise SettingValidationError.new(
              code: "migration_source_missing",
              message: "no compatible settings version is available to migrate"
            )
          end
          migrated_values = schema.migrate(
            read_values!(source),
            from_version: source.schema_version
          )
          record = append_version!(
            current:,
            values: migrated_values,
            change_kind: "migration",
            actor:,
            audit:,
            migration_source: source
          )
          snapshot_for(record)
        end
      rescue Lockbox::DecryptionError
        raise unreadable_settings_error
      end

      def rollback(revision:, expected_revision:, actor: nil, audit: {})
        target_revision = normalize_revision(revision, label: "rollback revision")

        mutate_with_lock do |current|
          assert_expected_revision!(current, expected_revision)
          unless current
            raise SettingValidationError.new(
              code: "not_configured",
              message: "plugin settings have no persisted version to roll back"
            )
          end
          target = PluginSettingVersion
            .for_namespace(plugin_id, schema.version)
            .find_by(revision: target_revision)
          unless target
            raise SettingValidationError.new(
              code: "rollback_target_missing",
              message: "the requested plugin settings revision does not exist"
            )
          end
          assert_schema_digest!(target)
          next snapshot_for(current) if target.id == current.id

          values = schema.validate_values(read_values!(target))
          record = append_version!(
            current:,
            values:,
            change_kind: "rollback",
            actor:,
            audit:,
            rollback_source: target
          )
          snapshot_for(record)
        end
      rescue Lockbox::DecryptionError
        raise unreadable_settings_error
      end

      def history(limit: 50)
        bounded_limit = limit.to_i.clamp(1, MAX_HISTORY)
        PluginSettingVersion
          .where(plugin_id:)
          .includes(:actor, :migration_source, :rollback_source)
          .order(id: :desc)
          .limit(bounded_limit)
          .map do |record|
            {
              id: record.id,
              schema_version: record.schema_version,
              schema_digest: record.schema_digest,
              revision: record.revision,
              change_kind: record.change_kind,
              actor: actor_snapshot(record.actor),
              migration_source: source_descriptor(record.migration_source),
              rollback_source: source_descriptor(record.rollback_source),
              current_schema: record.schema_version == schema.version &&
                record.schema_digest == schema.digest,
              created_at: record.created_at&.iso8601
            }.freeze
          end.freeze
      end

      private

      def mutate_with_lock
        PluginSettingVersion.transaction(requires_new: true) do
          acquire_advisory_lock!
          yield current_record
        end
      end

      def acquire_advisory_lock!
        connection = PluginSettingVersion.connection
        return unless connection.adapter_name.match?(/postgres/i)

        key = Digest::SHA256
          .digest("mcweb:plugin-settings:#{plugin_id}")
          .unpack1("q>")
        bind = ActiveRecord::Relation::QueryAttribute.new(
          "plugin_settings_advisory_lock_key",
          key,
          ActiveRecord::Type::Integer.new(limit: 8)
        )
        connection.exec_query(
          "SELECT pg_advisory_xact_lock($1)::text",
          "Plugin settings advisory lock",
          [ bind ]
        )
      end

      def current_record
        PluginSettingVersion
          .for_namespace(plugin_id, schema.version)
          .newest_first
          .first
      end

      def migration_source
        versions = PluginSettingVersion
          .where(plugin_id:)
          .where.not(schema_version: schema.version)
          .distinct
          .pluck(:schema_version)
          .select { |candidate| schema.migration_path_from(candidate).present? }
        return if versions.empty?

        PluginSettingVersion
          .where(plugin_id:, schema_version: versions)
          .order(id: :desc)
          .first
      end

      def pending_migration_source(current)
        source = migration_source
        return source unless current
        return source if source && source.id > current.id

        nil
      end

      def snapshot_for(record, migration_available: false)
        values = record ? read_values!(record) : schema.defaults.deep_dup
        if record
          assert_schema_digest!(record)
          values = schema.validate_values(values)
        end
        Snapshot.new(
          plugin_id:,
          schema_version: schema.version,
          schema_digest: schema.digest,
          revision: record&.revision || 0,
          values: deep_freeze(values.deep_stringify_keys),
          complete: (schema.required_keys - values.keys).empty?,
          migration_available: migration_available == true,
          persisted_at: record&.created_at&.iso8601
        )
      end

      def read_values!(record)
        values = record.values_hash
        unless values.is_a?(Hash)
          raise unreadable_settings_error
        end
        values
      end

      def append_version!(
        current:,
        values:,
        change_kind:,
        actor:,
        audit:,
        migration_source: nil,
        rollback_source: nil
      )
        revision = current ? current.revision + 1 : 1
        record = PluginSettingVersion.create!(
          plugin_id:,
          schema_version: schema.version,
          revision:,
          schema_digest: schema.digest,
          values: values.deep_stringify_keys,
          change_kind:,
          actor:,
          migration_source:,
          rollback_source:
        )
        before_values = current ? read_values!(current) : {}
        changed_keys = changed_keys_between(before_values, values)
        write_audit!(
          record:,
          current:,
          values:,
          before_values:,
          changed_keys:,
          change_kind:,
          actor:,
          audit:,
          migration_source:,
          rollback_source:
        )
        publish_change_after_commit(record, changed_keys)
        record
      end

      def write_audit!(
        record:,
        current:,
        values:,
        before_values:,
        changed_keys:,
        change_kind:,
        actor:,
        audit:,
        migration_source:,
        rollback_source:
      )
        AuditLog.record!(
          action: "plugin.settings.#{change_kind}",
          actor:,
          resource: record,
          metadata: {
            plugin_id:,
            schema_version: schema.version,
            schema_digest: schema.digest,
            revision: record.revision,
            changed_keys:,
            migration_source: source_descriptor(migration_source),
            rollback_source: source_descriptor(rollback_source)
          }.compact,
          before_state: audit_state(current, before_values),
          after_state: audit_state(record, values),
          ip_address: audit_value(audit, :ip_address),
          user_agent: audit_value(audit, :user_agent),
          reason: audit_value(audit, :reason)
        )
      end

      def changed_keys_between(before_values, after_values)
        (before_values.keys | after_values.keys).select do |key|
          before_values[key] != after_values[key]
        end.sort.freeze
      end

      def publish_change_after_commit(record, changed_keys)
        payload = {
          plugin_id:,
          schema_version: schema.version,
          schema_digest: schema.digest,
          revision: record.revision,
          change_kind: record.change_kind,
          changed_keys:
        }.freeze
        ActiveRecord.after_all_transactions_commit do
          Mcweb::Events.publish("plugin.settings.changed", payload)
        end
      end

      def audit_state(record, values)
        {
          schema_version: record&.schema_version,
          revision: record&.revision.to_i,
          configured_keys: values.keys.sort,
          sensitive_keys_configured: (values.keys & schema.sensitive_keys).sort
        }
      end

      def audit_value(audit, key)
        return unless audit.respond_to?(:[])

        audit[key] || audit[key.to_s]
      end

      def source_descriptor(record)
        return unless record

        {
          id: record.id,
          schema_version: record.schema_version,
          revision: record.revision
        }
      end

      def actor_snapshot(actor)
        return unless actor

        {
          public_id: actor.public_id,
          username: actor.username
        }
      end

      def assert_schema_digest!(record)
        return if record.schema_digest == schema.digest

        raise SettingValidationError.new(
          code: "schema_digest_mismatch",
          message: "plugin settings schema changed without a schema_version increment"
        )
      end

      def assert_expected_revision!(current, expected_revision)
        expected = normalize_revision(expected_revision, label: "expected revision", allow_zero: true)
        actual = current&.revision || 0
        return if expected == actual

        raise SettingValidationError.new(
          code: "revision_conflict",
          message: "plugin settings changed since they were loaded"
        )
      end

      def normalize_revision(value, label:, allow_zero: false)
        parsed = Integer(value, exception: false)
        minimum = allow_zero ? 0 : 1
        unless parsed && parsed >= minimum
          raise SettingValidationError.new(
            code: "invalid_argument",
            message: "#{label} is invalid"
          )
        end
        parsed
      end

      def normalize_unset_keys(value)
        unless value.is_a?(Array)
          raise SettingValidationError.new(
            code: "validation_failed",
            message: "unset_keys must be an array"
          )
        end
        keys = value.map(&:to_s)
        if keys.uniq.length != keys.length || (keys - schema.properties.keys).any?
          raise SettingValidationError.new(
            code: "validation_failed",
            message: "unset_keys contains an unknown or duplicate setting"
          )
        end
        keys.sort.freeze
      end

      def unreadable_settings_error
        SettingValidationError.new(
          code: "settings_unreadable",
          message: "plugin settings could not be decrypted or decoded"
        )
      end

      def deep_freeze(value)
        case value
        when Hash
          value.each { |key, item| deep_freeze(key); deep_freeze(item) }
        when Array
          value.each { |item| deep_freeze(item) }
        end
        value.freeze
      end
    end
  end
end
