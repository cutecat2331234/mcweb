# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "uri"
require "yaml"

module Mcweb
  module Plugins
    class SettingValidationError < Error
      attr_reader :code, :errors

      def initialize(code:, message:, errors: {})
        @code = code.to_s.freeze
        @errors = errors.deep_stringify_keys.freeze
        super(message)
      end
    end

    class SettingSchema
      DRAFT_URI = "https://json-schema.org/draft/2020-12/schema"
      VERSION_PATTERN = /\A[1-9]\d{0,8}\z/
      KEY_PATTERN = /\A[a-z][a-z0-9_]*(?:[.-][a-z0-9_]+)*\z/
      GROUP_PATTERN = /\A[a-z][a-z0-9_]*\z/
      PHRASE_PATTERN = /\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+\z/
      SUPPORTED_TYPES = %w[string integer number boolean].freeze
      SUPPORTED_FORMATS = %w[uri url email hostname].freeze
      SUPPORTED_INPUTS = %w[text password textarea url email select number switch].freeze
      ROOT_KEYS = %w[schema_version schema groups migrations].freeze
      JSON_SCHEMA_KEYS = %w[$schema type additionalProperties properties required].freeze
      GROUP_KEYS = %w[title_phrase description_phrase position].freeze
      PROPERTY_KEYS = %w[
        type default enum minLength maxLength minimum maximum pattern format
        x-mcweb-title-phrase x-mcweb-description-phrase x-mcweb-placeholder-phrase
        x-mcweb-group x-mcweb-sensitive x-mcweb-input x-mcweb-enum-phrases
      ].freeze
      MIGRATION_KEYS = %w[from to rename remove defaults].freeze
      MAX_PROPERTIES = 256
      MAX_GROUPS = 64
      MAX_MIGRATIONS = 64
      MAX_KEY_LENGTH = 191
      MAX_PHRASE_LENGTH = 191
      MAX_PATTERN_LENGTH = 512
      MAX_STRING_LENGTH = 65_536
      MAX_VALUES_BYTES = 1_048_576
      REGEXP_TIMEOUT_SECONDS = 0.05

      class Property
        attr_reader :key, :type, :default, :enum, :min_length, :max_length,
                    :minimum, :maximum, :pattern, :format, :title_phrase,
                    :description_phrase, :placeholder_phrase, :group, :input,
                    :enum_phrases

        def initialize(schema:, key:, attributes:)
          @schema = schema
          @key = schema.send(:normalize_setting_key, key)
          data = schema.send(
            :normalize_mapping,
            attributes,
            label: "settings schema property #{key.inspect}",
            allowed: PROPERTY_KEYS
          )
          @type = schema.send(:required_string, data, "type", label: property_label)
          unless SUPPORTED_TYPES.include?(@type)
            schema.send(:schema_error!, "#{property_label} has unsupported type #{@type.inspect}")
          end

          @title_phrase = schema.send(
            :required_phrase,
            data,
            "x-mcweb-title-phrase",
            label: property_label
          )
          @description_phrase = schema.send(
            :optional_phrase,
            data,
            "x-mcweb-description-phrase",
            label: property_label
          )
          @placeholder_phrase = schema.send(
            :optional_phrase,
            data,
            "x-mcweb-placeholder-phrase",
            label: property_label
          )
          @group = schema.send(:required_string, data, "x-mcweb-group", label: property_label)
          @sensitive = schema.send(
            :optional_boolean,
            data,
            "x-mcweb-sensitive",
            default: false,
            label: property_label
          )
          @enum = normalize_enum(data)
          @input = data.key?("x-mcweb-input") ?
            schema.send(:required_string, data, "x-mcweb-input", label: property_label) :
            inferred_input
          @enum_phrases = normalize_enum_phrases(data)
          @min_length = optional_integer(data, "minLength", minimum: 0)
          @max_length = optional_integer(data, "maxLength", minimum: 0, maximum: MAX_STRING_LENGTH)
          @minimum = optional_number(data, "minimum")
          @maximum = optional_number(data, "maximum")
          @pattern = normalize_pattern(data["pattern"])
          @format = normalize_format(data["format"])
          @has_default = data.key?("default")
          if @has_default
            @default = schema.send(
              :deep_freeze,
              schema.send(:deep_copy, data["default"])
            )
          end
          validate_declaration!
          freeze
        end

        def sensitive?
          @sensitive
        end

        def has_default?
          @has_default
        end

        def validate_value(value)
          errors = []
          errors << "must be a #{type}" unless value_matches_type?(value)
          return errors unless errors.empty?

          if enum && !enum.include?(value)
            errors << "must be one of the declared enum values"
          end
          if value.is_a?(String)
            errors << "is shorter than minLength" if min_length && value.length < min_length
            errors << "is longer than maxLength" if max_length && value.length > max_length
            if pattern
              begin
                errors << "does not match the declared pattern" unless pattern.match?(value)
              rescue Regexp::TimeoutError
                errors << "does not match the declared pattern"
              end
            end
            errors << "does not match the declared format" if format && !matches_format?(value)
          elsif value.is_a?(Numeric)
            errors << "is below minimum" if minimum && value < minimum
            errors << "is above maximum" if maximum && value > maximum
          end
          errors
        end

        def to_h
          {
            "key" => key,
            "type" => type,
            "required" => @schema.required_keys.include?(key),
            "sensitive" => sensitive?,
            "group" => group,
            "input" => input,
            "title_phrase" => title_phrase,
            "description_phrase" => description_phrase,
            "placeholder_phrase" => placeholder_phrase,
            "enum" => enum,
            "enum_phrases" => enum_phrases,
            "minimum" => minimum,
            "maximum" => maximum,
            "min_length" => min_length,
            "max_length" => max_length,
            "pattern" => pattern&.source,
            "format" => format,
            "has_default" => has_default?,
            "default" => sensitive? || !has_default? ? nil : @schema.send(:deep_copy, default)
          }.freeze
        end

        private

        def property_label
          "settings schema property #{key.inspect}"
        end

        def inferred_input
          return "password" if sensitive?
          return "select" if @enum

          {
            "string" => "text",
            "integer" => "number",
            "number" => "number",
            "boolean" => "switch"
          }.fetch(type)
        end

        def normalize_enum(data)
          return unless data.key?("enum")

          values = data["enum"]
          unless values.is_a?(Array) && values.length.between?(1, 100)
            @schema.send(:schema_error!, "#{property_label} enum must contain between 1 and 100 values")
          end
          normalized = values.map { |value| @schema.send(:deep_copy, value) }
          unless normalized.uniq.length == normalized.length
            @schema.send(:schema_error!, "#{property_label} enum values must be unique")
          end
          @schema.send(:deep_freeze, normalized)
        end

        def normalize_enum_phrases(data)
          return {}.freeze unless data.key?("x-mcweb-enum-phrases")
          unless @enum
            @schema.send(:schema_error!, "#{property_label} enum phrases require enum")
          end

          mapping = @schema.send(
            :normalize_mapping,
            data["x-mcweb-enum-phrases"],
            label: "#{property_label} enum phrases"
          )
          expected_keys = @enum.map { |value| enum_key(value) }
          unless expected_keys.uniq.length == expected_keys.length
            @schema.send(
              :schema_error!,
              "#{property_label} enum values must have unique serialized keys"
            )
          end
          unless mapping.keys.sort == expected_keys.sort
            @schema.send(
              :schema_error!,
              "#{property_label} enum phrases must define every enum value exactly once"
            )
          end
          mapping.sort.to_h do |value, phrase|
            [
              value.freeze,
              @schema.send(
                :validate_phrase,
                phrase,
                label: "#{property_label} enum phrase #{value.inspect}"
              )
            ]
          end.freeze
        end

        def enum_key(value)
          case value
          when String then value
          when Integer, Float, TrueClass, FalseClass then JSON.generate(value)
          else
            @schema.send(:schema_error!, "#{property_label} enum values must be JSON scalars")
          end
        end

        def optional_integer(data, key, minimum:, maximum: nil)
          return unless data.key?(key)

          value = data[key]
          unless value.is_a?(Integer) && value >= minimum && (!maximum || value <= maximum)
            @schema.send(:schema_error!, "#{property_label} #{key} is outside the supported range")
          end
          value
        end

        def optional_number(data, key)
          return unless data.key?(key)

          value = data[key]
          unless value.is_a?(Numeric) && value.finite?
            @schema.send(:schema_error!, "#{property_label} #{key} must be a finite number")
          end
          value
        end

        def normalize_pattern(value)
          return if value.nil?
          unless value.is_a?(String) && value.length <= MAX_PATTERN_LENGTH
            @schema.send(:schema_error!, "#{property_label} pattern is invalid")
          end

          Regexp.new(value, timeout: REGEXP_TIMEOUT_SECONDS).freeze
        rescue RegexpError => e
          @schema.send(:schema_error!, "#{property_label} pattern is invalid: #{e.message}")
        end

        def normalize_format(value)
          return if value.nil?
          unless value.is_a?(String) && SUPPORTED_FORMATS.include?(value)
            @schema.send(:schema_error!, "#{property_label} format is unsupported")
          end
          value.freeze
        end

        def validate_declaration!
          unless @schema.group_keys.include?(group)
            @schema.send(:schema_error!, "#{property_label} references unknown group #{group.inspect}")
          end
          unless SUPPORTED_INPUTS.include?(input)
            @schema.send(:schema_error!, "#{property_label} input #{input.inspect} is unsupported")
          end
          if sensitive? && (type != "string" || input != "password" || has_default? || enum)
            @schema.send(
              :schema_error!,
              "#{property_label} sensitive values must be password strings without defaults or enum values"
            )
          end
          if %w[minLength maxLength pattern format].any? { |key| declaration_value?(key) } &&
              type != "string"
            @schema.send(:schema_error!, "#{property_label} uses string-only constraints")
          end
          if %w[minimum maximum].any? { |key| declaration_value?(key) } &&
              !%w[integer number].include?(type)
            @schema.send(:schema_error!, "#{property_label} uses number-only constraints")
          end
          if min_length && max_length && min_length > max_length
            @schema.send(:schema_error!, "#{property_label} minLength exceeds maxLength")
          end
          if minimum && maximum && minimum > maximum
            @schema.send(:schema_error!, "#{property_label} minimum exceeds maximum")
          end
          if input == "select" && !enum
            @schema.send(:schema_error!, "#{property_label} select input requires enum")
          end
          if input == "switch" && type != "boolean"
            @schema.send(:schema_error!, "#{property_label} switch input requires boolean")
          end
          if input == "number" && !%w[integer number].include?(type)
            @schema.send(:schema_error!, "#{property_label} number input requires a numeric type")
          end
          if %w[url email].include?(input) && type != "string"
            @schema.send(:schema_error!, "#{property_label} #{input} input requires a string type")
          end

          validate_declared_values!
        end

        def declaration_value?(key)
          value = {
            "minLength" => min_length,
            "maxLength" => max_length,
            "pattern" => pattern,
            "format" => format,
            "minimum" => minimum,
            "maximum" => maximum
          }.fetch(key)
          !value.nil?
        end

        def validate_declared_values!
          if enum
            enum.each do |value|
              errors = validate_value(value)
              unless errors.empty?
                @schema.send(:schema_error!, "#{property_label} enum #{errors.join(', ')}")
              end
            end
          end
          return unless has_default?

          errors = validate_value(default)
          unless errors.empty?
            @schema.send(:schema_error!, "#{property_label} default #{errors.join(', ')}")
          end
        end

        def value_matches_type?(value)
          case type
          when "string"
            value.is_a?(String)
          when "integer"
            value.is_a?(Integer)
          when "number"
            value.is_a?(Numeric) && value.finite?
          when "boolean"
            value == true || value == false
          else
            false
          end
        end

        def matches_format?(value)
          case format
          when "uri"
            parsed = URI.parse(value)
            parsed.scheme.present? && !value.match?(/\s/)
          when "url"
            parsed = URI.parse(value)
            %w[http https].include?(parsed.scheme) && parsed.host.present? && !value.match?(/\s/)
          when "email"
            value.match?(URI::MailTo::EMAIL_REGEXP)
          when "hostname"
            value.present? && value.length <= 253 &&
              value.split(".").all? { |part| part.match?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/i) }
          else
            true
          end
        rescue URI::InvalidURIError
          false
        end
      end

      class Migration
        attr_reader :from, :to, :rename, :remove, :defaults

        def initialize(schema:, attributes:)
          @schema = schema
          data = schema.send(
            :normalize_mapping,
            attributes,
            label: "settings schema migration",
            allowed: MIGRATION_KEYS
          )
          @from = schema.send(:normalize_version, data["from"], label: "migration from")
          @to = schema.send(:normalize_version, data["to"], label: "migration to")
          unless from.to_i < to.to_i && to.to_i <= schema.version.to_i
            schema.send(:schema_error!, "settings migration versions must move forward to the current schema")
          end
          @rename = normalize_rename(data.fetch("rename", {}))
          @remove = normalize_remove(data.fetch("remove", []))
          @defaults = normalize_defaults(data.fetch("defaults", {}))
          if rename.empty? && remove.empty? && defaults.empty?
            schema.send(:schema_error!, "settings migration must declare at least one operation")
          end
          unless (rename.keys & remove).empty?
            schema.send(:schema_error!, "settings migration cannot both rename and remove the same key")
          end
          freeze
        end

        def apply(values)
          migrated = values.deep_stringify_keys
          rename.each do |source, destination|
            next unless migrated.key?(source)
            if source != destination && migrated.key?(destination)
              raise SettingValidationError.new(
                code: "migration_conflict",
                message: "settings migration cannot overwrite #{destination.inspect}"
              )
            end

            migrated[destination] = migrated.delete(source)
          end
          remove.each { |key| migrated.delete(key) }
          defaults.each do |key, value|
            migrated[key] = @schema.send(:deep_copy, value) unless migrated.key?(key)
          end
          migrated
        end

        def to_h
          {
            "from" => from,
            "to" => to,
            "rename" => rename,
            "remove" => remove,
            "defaults" => defaults
          }.freeze
        end

        private

        def normalize_rename(value)
          mapping = @schema.send(:normalize_mapping, value, label: "settings migration rename")
          normalized = mapping.to_h do |source, destination|
            [
              @schema.send(:normalize_setting_key, source),
              @schema.send(:normalize_setting_key, destination)
            ]
          end
          unless normalized.values.uniq.length == normalized.values.length
            @schema.send(:schema_error!, "settings migration rename destinations must be unique")
          end
          normalized.sort.to_h.freeze
        end

        def normalize_remove(value)
          unless value.is_a?(Array)
            @schema.send(:schema_error!, "settings migration remove must be an array")
          end
          keys = value.map { |key| @schema.send(:normalize_setting_key, key) }
          unless keys.uniq.length == keys.length
            @schema.send(:schema_error!, "settings migration remove keys must be unique")
          end
          keys.sort.freeze
        end

        def normalize_defaults(value)
          mapping = @schema.send(:normalize_mapping, value, label: "settings migration defaults")
          mapping.sort.to_h do |key, default|
            normalized_key = @schema.send(:normalize_setting_key, key)
            unless @schema.send(:json_scalar?, default)
              @schema.send(:schema_error!, "settings migration defaults must be JSON scalars")
            end
            [
              normalized_key,
              @schema.send(
                :deep_freeze,
                @schema.send(:deep_copy, default)
              )
            ]
          end.freeze
        end
      end

      attr_reader :plugin_id, :version, :digest, :properties, :required_keys,
                  :groups, :migrations

      def initialize(plugin_id:, document:)
        @plugin_id = plugin_id.to_s.dup.freeze
        @phrase_namespace = plugin_id.to_s.tr("/-", "._").freeze
        root = normalize_mapping(
          document,
          label: "settings contribution root",
          allowed: ROOT_KEYS
        )
        missing = %w[schema_version schema groups] - root.keys
        schema_error!("settings contribution is missing: #{missing.join(', ')}") if missing.any?

        @version = normalize_version(root["schema_version"], label: "schema_version")
        @groups = normalize_groups(root["groups"])
        @group_keys = @groups.keys.freeze
        @properties, @required_keys = normalize_json_schema(root["schema"])
        @migrations = normalize_migrations(root.fetch("migrations", []))
        validate_migration_paths!
        @digest = Digest::SHA256.hexdigest(JSON.generate(canonical_hash)).freeze
        freeze
      end

      def group_keys
        @group_keys
      end

      def defaults
        properties.each_with_object({}) do |(key, property), values|
          values[key] = deep_copy(property.default) if property.has_default?
        end.freeze
      end

      def sensitive_keys
        properties.values.select(&:sensitive?).map(&:key).sort.freeze
      end

      def validate_values(values)
        normalized = normalize_values_mapping(values)
        errors = {}

        unknown = normalized.keys - properties.keys
        unknown.sort.each { |key| errors[key] = [ "is not declared by the settings schema" ] }
        (required_keys - normalized.keys).sort.each { |key| errors[key] = [ "is required" ] }
        (normalized.keys & properties.keys).sort.each do |key|
          field_errors = properties.fetch(key).validate_value(normalized.fetch(key))
          errors[key] = field_errors unless field_errors.empty?
        end

        unless errors.empty?
          raise SettingValidationError.new(
            code: "validation_failed",
            message: "plugin settings failed schema validation",
            errors:
          )
        end
        if JSON.generate(normalized).bytesize > MAX_VALUES_BYTES
          raise SettingValidationError.new(
            code: "payload_too_large",
            message: "plugin settings exceed the maximum encoded size"
          )
        end

        deep_freeze(normalized)
      rescue JSON::GeneratorError
        raise SettingValidationError.new(
          code: "validation_failed",
          message: "plugin settings must contain only supported JSON scalar values"
        )
      end

      def validate_partial_values(values)
        normalized = normalize_values_mapping(values)
        errors = {}
        unknown = normalized.keys - properties.keys
        unknown.sort.each { |key| errors[key] = [ "is not declared by the settings schema" ] }
        (normalized.keys & properties.keys).sort.each do |key|
          field_errors = properties.fetch(key).validate_value(normalized.fetch(key))
          errors[key] = field_errors unless field_errors.empty?
        end
        unless errors.empty?
          raise SettingValidationError.new(
            code: "validation_failed",
            message: "plugin settings failed schema validation",
            errors:
          )
        end

        deep_freeze(normalized)
      end

      def migration_path_from(from_version)
        from_version = normalize_version(from_version, label: "source schema version")
        return [].freeze if from_version == version
        return nil if from_version.to_i > version.to_i

        path = []
        cursor = from_version
        seen = {}
        while cursor != version
          return nil if seen[cursor]

          seen[cursor] = true
          step = migrations.find { |migration| migration.from == cursor }
          return nil unless step

          path << step
          cursor = step.to
        end
        path.freeze
      end

      def migrate(values, from_version:)
        path = migration_path_from(from_version)
        unless path
          raise SettingValidationError.new(
            code: "migration_path_missing",
            message: "no settings migration path from schema #{from_version} to #{version}"
          )
        end

        migrated = normalize_values_mapping(values)
        path.each { |migration| migrated = migration.apply(migrated) }
        validate_values(migrated)
      end

      def to_h
        {
          "plugin_id" => plugin_id,
          "schema_version" => version,
          "schema_digest" => digest,
          "groups" => groups,
          "properties" => properties.values.sort_by(&:key).map(&:to_h),
          "required" => required_keys,
          "migrations" => migrations.map(&:to_h)
        }.freeze
      end

      private

      def normalize_groups(value)
        mapping = normalize_mapping(value, label: "settings groups")
        schema_error!("settings schema has too many groups") if mapping.length > MAX_GROUPS
        schema_error!("settings schema must declare at least one group") if mapping.empty?

        mapping.sort.to_h do |raw_key, attributes|
          key = raw_key.to_s
          unless key.length.between?(1, 64) && key.match?(GROUP_PATTERN)
            schema_error!("invalid settings group #{key.inspect}")
          end
          data = normalize_mapping(
            attributes,
            label: "settings group #{key.inspect}",
            allowed: GROUP_KEYS
          )
          missing = %w[title_phrase position] - data.keys
          schema_error!("settings group #{key.inspect} is missing: #{missing.join(', ')}") if missing.any?
          position = data["position"]
          unless position.is_a?(Integer) && position.between?(0, 10_000)
            schema_error!("settings group #{key.inspect} position is invalid")
          end

          [
            key.freeze,
            {
              "key" => key.freeze,
              "title_phrase" => validate_phrase(
                data["title_phrase"],
                label: "settings group #{key.inspect} title_phrase"
              ),
              "description_phrase" => optional_phrase(
                data,
                "description_phrase",
                label: "settings group #{key.inspect}"
              ),
              "position" => position
            }.freeze
          ]
        end.freeze
      end

      def normalize_json_schema(value)
        schema = normalize_mapping(
          value,
          label: "settings JSON Schema",
          allowed: JSON_SCHEMA_KEYS
        )
        required_root = %w[$schema type additionalProperties properties]
        missing = required_root - schema.keys
        schema_error!("settings JSON Schema is missing: #{missing.join(', ')}") if missing.any?
        unless schema["$schema"] == DRAFT_URI
          schema_error!("settings JSON Schema must declare #{DRAFT_URI}")
        end
        schema_error!("settings JSON Schema root type must be object") unless schema["type"] == "object"
        unless schema["additionalProperties"] == false
          schema_error!("settings JSON Schema must set additionalProperties to false")
        end

        property_mapping = normalize_mapping(schema["properties"], label: "settings properties")
        schema_error!("settings schema has too many properties") if property_mapping.length > MAX_PROPERTIES
        normalized_properties = property_mapping.sort.to_h do |key, attributes|
          property = Property.new(schema: self, key:, attributes:)
          [ property.key, property ]
        end.freeze

        required = schema.fetch("required", [])
        schema_error!("settings JSON Schema required must be an array") unless required.is_a?(Array)
        normalized_required = required.map { |key| normalize_setting_key(key) }
        unless normalized_required.uniq.length == normalized_required.length
          schema_error!("settings JSON Schema required keys must be unique")
        end
        unknown_required = normalized_required - normalized_properties.keys
        if unknown_required.any?
          schema_error!("settings JSON Schema requires unknown keys: #{unknown_required.sort.join(', ')}")
        end

        [ normalized_properties, normalized_required.sort.freeze ]
      end

      def normalize_migrations(value)
        schema_error!("settings migrations must be an array") unless value.is_a?(Array)
        schema_error!("settings schema has too many migrations") if value.length > MAX_MIGRATIONS

        normalized = value.map { |attributes| Migration.new(schema: self, attributes:) }
        duplicate_sources = normalized.group_by(&:from).select { |_version, entries| entries.length > 1 }.keys
        if duplicate_sources.any?
          schema_error!("settings migrations have duplicate sources: #{duplicate_sources.sort.join(', ')}")
        end
        normalized.sort_by { |migration| migration.from.to_i }.freeze
      end

      def validate_migration_paths!
        migrations.each do |migration|
          unless migration_path_from(migration.from)
            schema_error!("settings migration from #{migration.from} does not reach schema #{version}")
          end
        end
      end

      def normalize_values_mapping(value)
        unless value.is_a?(Hash)
          raise SettingValidationError.new(
            code: "validation_failed",
            message: "plugin settings values must be a mapping"
          )
        end

        value.each_with_object({}) do |(key, item), values|
          unless key.is_a?(String) || key.is_a?(Symbol)
            raise SettingValidationError.new(
              code: "validation_failed",
              message: "plugin setting keys must be strings"
            )
          end
          normalized_key = key.to_s
          unless normalized_key.length.between?(1, MAX_KEY_LENGTH) &&
              normalized_key.match?(KEY_PATTERN)
            raise SettingValidationError.new(
              code: "validation_failed",
              message: "plugin setting key is invalid"
            )
          end
          if values.key?(normalized_key)
            raise SettingValidationError.new(
              code: "validation_failed",
              message: "plugin setting keys must be unique"
            )
          end
          unless json_scalar?(item)
            raise SettingValidationError.new(
              code: "validation_failed",
              message: "plugin setting #{normalized_key.inspect} must be a supported JSON scalar",
              errors: { normalized_key => [ "must be a supported JSON scalar" ] }
            )
          end
          values[normalized_key] = deep_copy(item)
        end
      end

      def normalize_mapping(value, label:, allowed: nil)
        schema_error!("#{label} must be a mapping") unless value.is_a?(Hash)

        normalized = value.each_with_object({}) do |(raw_key, item), result|
          unless raw_key.is_a?(String) || raw_key.is_a?(Symbol)
            schema_error!("#{label} keys must be strings")
          end
          key = raw_key.to_s
          schema_error!("duplicate #{label} key #{key.inspect}") if result.key?(key)
          result[key] = item
        end
        if allowed
          unknown = normalized.keys - allowed
          schema_error!("unknown #{label} keys: #{unknown.sort.join(', ')}") if unknown.any?
        end
        normalized
      end

      def required_string(data, key, label:)
        value = data[key]
        unless value.is_a?(String) && value.present?
          schema_error!("#{label} #{key} must be a non-empty string")
        end
        value.dup.freeze
      end

      def optional_boolean(data, key, default:, label:)
        return default unless data.key?(key)
        value = data[key]
        unless value == true || value == false
          schema_error!("#{label} #{key} must be a boolean")
        end
        value
      end

      def required_phrase(data, key, label:)
        validate_phrase(data[key], label: "#{label} #{key}")
      end

      def optional_phrase(data, key, label:)
        return unless data.key?(key)

        validate_phrase(data[key], label: "#{label} #{key}")
      end

      def validate_phrase(value, label:)
        unless value.is_a?(String) &&
            value.length.between?(1, MAX_PHRASE_LENGTH) &&
            value.match?(PHRASE_PATTERN) &&
            value.start_with?("#{@phrase_namespace}.")
          schema_error!("#{label} must remain in the #{@phrase_namespace} phrase namespace")
        end
        value.dup.freeze
      end

      def normalize_version(value, label:)
        unless value.is_a?(String) && value.length <= 32 && value.match?(VERSION_PATTERN)
          schema_error!("#{label} must be a positive integer string")
        end
        value.dup.freeze
      end

      def normalize_setting_key(value)
        unless value.is_a?(String) || value.is_a?(Symbol)
          schema_error!("setting keys must be strings")
        end
        key = value.to_s
        unless key.length.between?(1, MAX_KEY_LENGTH) && key.match?(KEY_PATTERN)
          schema_error!("invalid setting key #{key.inspect}")
        end
        key.freeze
      end

      def json_scalar?(value)
        value.nil? || value == true || value == false || value.is_a?(String) ||
          value.is_a?(Integer) || (value.is_a?(Float) && value.finite?)
      end

      def canonical_hash
        canonicalize(
          {
            "schema_version" => version,
            "groups" => groups,
            "properties" => properties.transform_values(&:to_h),
            "required" => required_keys,
            "migrations" => migrations.map(&:to_h)
          }
        )
      end

      def canonicalize(value)
        case value
        when Hash
          value.keys.map(&:to_s).sort.to_h do |key|
            item = value.key?(key) ? value[key] : value[key.to_sym]
            [ key, canonicalize(item) ]
          end
        when Array
          value.map { |item| canonicalize(item) }
        when Regexp
          value.source
        else
          value
        end
      end

      def deep_copy(value)
        case value
        when String then value.dup
        when Hash then value.to_h { |key, item| [ key.to_s.dup, deep_copy(item) ] }
        when Array then value.map { |item| deep_copy(item) }
        else value
        end
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

      def schema_error!(message)
        raise ManifestError, message
      end

      alias_method :schema_error, :schema_error!
    end

    class SettingSchemaLoader
      MAX_FILE_BYTES = 1_048_576

      def self.load(manifest)
        new(manifest).load
      end

      def initialize(manifest)
        @manifest = manifest
      end

      def load
        relative_path = @manifest.settings_contribution_path
        return unless relative_path
        unless @manifest.source_path
          raise ManifestError, "settings contribution requires a file-backed manifest"
        end

        source = resolve_source(relative_path)
        yaml = read_yaml(source)
        parsed = YAML.safe_load(
          yaml,
          permitted_classes: [],
          permitted_symbols: [],
          aliases: false
        )
        SettingSchema.new(plugin_id: @manifest.id, document: parsed)
      rescue Psych::Exception => e
        raise ManifestError, "invalid safe settings contribution YAML: #{e.message}"
      rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP => e
        raise ManifestError, "invalid settings contribution file: #{e.message}"
      end

      private

      def resolve_source(relative_path)
        root = Pathname(@manifest.source_path).dirname.realpath
        candidate = root.join(relative_path).cleanpath
        unless candidate.file?
          raise ManifestError, "settings contribution does not exist: #{candidate}"
        end

        candidate_real = candidate.realpath
        unless contained_path?(candidate_real, root)
          raise ManifestError, "settings contribution must remain inside the plugin directory"
        end
        candidate_real
      end

      def read_yaml(source)
        yaml = File.open(source, "rb") { |file| file.read(MAX_FILE_BYTES + 1) }
        raise ManifestError, "settings contribution is too large" if yaml.bytesize > MAX_FILE_BYTES

        yaml.force_encoding(Encoding::UTF_8)
        raise ManifestError, "settings contribution must be valid UTF-8" unless yaml.valid_encoding?

        yaml.delete_prefix!("\uFEFF")
        reject_duplicate_mapping_keys!(yaml)
        yaml
      end

      def reject_duplicate_mapping_keys!(yaml)
        visit_yaml_node(Psych.parse_stream(yaml))
      end

      def visit_yaml_node(node)
        case node
        when Psych::Nodes::Mapping
          seen = {}
          node.children.each_slice(2) do |key, value|
            unless key.is_a?(Psych::Nodes::Scalar)
              raise ManifestError, "settings contribution mapping keys must be scalar strings"
            end
            normalized_key = key.value.to_s
            if seen.key?(normalized_key)
              raise ManifestError, "duplicate settings contribution key #{normalized_key.inspect}"
            end

            seen[normalized_key] = true
            visit_yaml_node(value)
          end
        when Psych::Nodes::Stream, Psych::Nodes::Document, Psych::Nodes::Sequence
          node.children.each { |child| visit_yaml_node(child) }
        end
      end

      def contained_path?(candidate, root)
        relative = candidate.relative_path_from(root)
        !relative.absolute? && relative.each_filename.first != ".."
      rescue ArgumentError
        false
      end
    end
  end
end
