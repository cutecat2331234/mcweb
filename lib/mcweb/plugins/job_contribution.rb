# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "uri"
require "yaml"

module Mcweb
  module Plugins
    class JobValidationError < Error
      attr_reader :code, :errors

      def initialize(code:, message:, errors: {})
        @code = code.to_s.freeze
        @errors = errors.deep_stringify_keys.freeze
        super(message)
      end
    end

    class JobDispatchError < Error
      attr_reader :code

      def initialize(code:, message:)
        @code = code.to_s.freeze
        super(message)
      end
    end

    class JobContribution
      DRAFT_URI = "https://json-schema.org/draft/2020-12/schema"
      VERSION_PATTERN = /\A[1-9]\d{0,8}\z/
      JOB_KEY_PATTERN = /\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*\z/
      ARGUMENT_KEY_PATTERN = /\A[a-z][a-z0-9_]*\z/
      SUPPORTED_TYPES = %w[string integer number boolean].freeze
      SUPPORTED_FORMATS = %w[uri url email hostname uuid].freeze
      ROOT_KEYS = %w[schema_version jobs].freeze
      JOB_KEYS = %w[arguments max_attempts retry_wait_seconds lease_seconds].freeze
      ARGUMENT_SCHEMA_KEYS = %w[$schema type additionalProperties properties required].freeze
      PROPERTY_KEYS = %w[type enum minLength maxLength minimum maximum format].freeze
      MAX_JOBS = 128
      MAX_ARGUMENTS = 64
      MAX_KEY_LENGTH = 191
      MAX_STRING_LENGTH = 65_536
      MAX_ARGUMENT_BYTES = 262_144

      class Property
        attr_reader :key, :type, :enum, :min_length, :max_length, :minimum,
                    :maximum, :format

        def initialize(contribution:, key:, attributes:)
          @contribution = contribution
          @key = contribution.send(:normalize_argument_key, key)
          data = contribution.send(
            :normalize_mapping,
            attributes,
            label: "plugin job argument #{key.inspect}",
            allowed: PROPERTY_KEYS
          )
          @type = contribution.send(:required_string, data, "type", label:)
          unless SUPPORTED_TYPES.include?(type)
            contribution.send(:schema_error!, "#{label} has unsupported type #{type.inspect}")
          end

          @enum = normalize_enum(data)
          @min_length = optional_integer(data, "minLength", minimum: 0, maximum: MAX_STRING_LENGTH)
          @max_length = optional_integer(data, "maxLength", minimum: 0, maximum: MAX_STRING_LENGTH)
          @minimum = optional_number(data, "minimum")
          @maximum = optional_number(data, "maximum")
          @format = normalize_format(data["format"])
          validate_declaration!
          freeze
        end

        def validate(value)
          errors = []
          errors << "must be a #{type}" unless matches_type?(value)
          return errors unless errors.empty?

          errors << "must be one of the declared enum values" if enum && !enum.include?(value)
          if value.is_a?(String)
            errors << "is shorter than minLength" if min_length && value.length < min_length
            errors << "is longer than maxLength" if max_length && value.length > max_length
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
            "enum" => enum,
            "min_length" => min_length,
            "max_length" => max_length,
            "minimum" => minimum,
            "maximum" => maximum,
            "format" => format
          }.freeze
        end

        private

        def label
          "plugin job argument #{key.inspect}"
        end

        def normalize_enum(data)
          return unless data.key?("enum")

          values = data["enum"]
          unless values.is_a?(Array) && values.length.between?(1, 100)
            @contribution.send(:schema_error!, "#{label} enum must contain between 1 and 100 values")
          end
          normalized = values.map { |value| @contribution.send(:deep_copy, value) }
          unless normalized.all? { |value| @contribution.send(:json_scalar?, value) } &&
              normalized.uniq.length == normalized.length
            @contribution.send(:schema_error!, "#{label} enum must contain unique JSON scalar values")
          end
          @contribution.send(:deep_freeze, normalized)
        end

        def optional_integer(data, key, minimum:, maximum:)
          return unless data.key?(key)

          value = data[key]
          unless value.is_a?(Integer) && value.between?(minimum, maximum)
            @contribution.send(:schema_error!, "#{label} #{key} is outside the supported range")
          end
          value
        end

        def optional_number(data, key)
          return unless data.key?(key)

          value = data[key]
          unless value.is_a?(Numeric) && value.finite?
            @contribution.send(:schema_error!, "#{label} #{key} must be a finite number")
          end
          value
        end

        def normalize_format(value)
          return if value.nil?
          unless value.is_a?(String) && SUPPORTED_FORMATS.include?(value)
            @contribution.send(:schema_error!, "#{label} format is unsupported")
          end
          value.freeze
        end

        def validate_declaration!
          if (!min_length.nil? || !max_length.nil? || format) && type != "string"
            @contribution.send(:schema_error!, "#{label} uses string-only constraints")
          end
          if (!minimum.nil? || !maximum.nil?) && !%w[integer number].include?(type)
            @contribution.send(:schema_error!, "#{label} uses number-only constraints")
          end
          if min_length && max_length && min_length > max_length
            @contribution.send(:schema_error!, "#{label} minLength exceeds maxLength")
          end
          if minimum && maximum && minimum > maximum
            @contribution.send(:schema_error!, "#{label} minimum exceeds maximum")
          end
          return unless enum

          enum.each do |value|
            errors = validate(value)
            next if errors.empty?

            @contribution.send(:schema_error!, "#{label} enum #{errors.join(', ')}")
          end
        end

        def matches_type?(value)
          case type
          when "string" then value.is_a?(String)
          when "integer" then value.is_a?(Integer)
          when "number"
            value.is_a?(Integer) || (value.is_a?(Float) && value.finite?)
          when "boolean" then value == true || value == false
          else false
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
              value.split(".").all? {
                |part| part.match?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/i)
              }
          when "uuid"
            value.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i)
          else
            true
          end
        rescue URI::InvalidURIError
          false
        end
      end

      class Definition
        attr_reader :plugin_id, :key, :properties, :required_keys, :max_attempts,
                    :retry_wait_seconds, :lease_seconds, :digest

        def initialize(contribution:, key:, attributes:)
          @plugin_id = contribution.plugin_id
          @key = contribution.send(:normalize_job_key, key)
          data = contribution.send(
            :normalize_mapping,
            attributes,
            label: "plugin job #{key.inspect}",
            allowed: JOB_KEYS
          )
          missing = %w[arguments] - data.keys
          if missing.any?
            contribution.send(:schema_error!, "plugin job #{key.inspect} is missing: #{missing.join(', ')}")
          end
          @properties, @required_keys = normalize_argument_schema(
            contribution,
            data.fetch("arguments")
          )
          @max_attempts = bounded_integer(
            contribution,
            data.fetch("max_attempts", 3),
            key: "max_attempts",
            range: 1..10
          )
          @retry_wait_seconds = bounded_integer(
            contribution,
            data.fetch("retry_wait_seconds", 60),
            key: "retry_wait_seconds",
            range: 0..86_400
          )
          @lease_seconds = bounded_integer(
            contribution,
            data.fetch("lease_seconds", 900),
            key: "lease_seconds",
            range: 30..3_600
          )
          @digest = Digest::SHA256.hexdigest(JSON.generate(canonical_hash)).freeze
          freeze
        end

        def qualified_key
          "#{plugin_id}:#{key}".freeze
        end

        def validate_arguments(arguments)
          unless arguments.is_a?(Hash)
            raise JobValidationError.new(
              code: "validation_failed",
              message: "plugin job arguments must be a mapping"
            )
          end

          normalized = arguments.each_with_object({}) do |(raw_key, value), result|
            unless raw_key.is_a?(String) || raw_key.is_a?(Symbol)
              raise JobValidationError.new(
                code: "validation_failed",
                message: "plugin job argument keys must be strings"
              )
            end
            argument_key = raw_key.to_s
            if result.key?(argument_key)
              raise JobValidationError.new(
                code: "validation_failed",
                message: "plugin job argument keys must be unique"
              )
            end
            result[argument_key] = value
          end

          errors = {}
          (normalized.keys - properties.keys).sort.each do |argument_key|
            errors[argument_key] = [ "is not declared by the job schema" ]
          end
          (required_keys - normalized.keys).sort.each do |argument_key|
            errors[argument_key] = [ "is required" ]
          end
          (normalized.keys & properties.keys).sort.each do |argument_key|
            field_errors = properties.fetch(argument_key).validate(normalized.fetch(argument_key))
            errors[argument_key] = field_errors unless field_errors.empty?
          end
          unless errors.empty?
            raise JobValidationError.new(
              code: "validation_failed",
              message: "plugin job arguments failed schema validation",
              errors:
            )
          end
          if JSON.generate(normalized).bytesize > MAX_ARGUMENT_BYTES
            raise JobValidationError.new(
              code: "payload_too_large",
              message: "plugin job arguments exceed the maximum encoded size"
            )
          end

          deep_freeze(normalized.deep_stringify_keys)
        rescue JSON::GeneratorError
          raise JobValidationError.new(
            code: "validation_failed",
            message: "plugin job arguments must contain supported JSON scalar values"
          )
        end

        def to_h
          {
            "plugin_id" => plugin_id,
            "key" => key,
            "qualified_key" => qualified_key,
            "digest" => digest,
            "properties" => properties.values.sort_by(&:key).map(&:to_h),
            "required" => required_keys,
            "max_attempts" => max_attempts,
            "retry_wait_seconds" => retry_wait_seconds,
            "lease_seconds" => lease_seconds
          }.freeze
        end

        private

        def normalize_argument_schema(contribution, value)
          schema = contribution.send(
            :normalize_mapping,
            value,
            label: "plugin job #{key.inspect} argument schema",
            allowed: ARGUMENT_SCHEMA_KEYS
          )
          missing = %w[$schema type additionalProperties properties] - schema.keys
          if missing.any?
            contribution.send(
              :schema_error!,
              "plugin job #{key.inspect} argument schema is missing: #{missing.join(', ')}"
            )
          end
          unless schema["$schema"] == DRAFT_URI &&
              schema["type"] == "object" &&
              schema["additionalProperties"] == false
            contribution.send(
              :schema_error!,
              "plugin job #{key.inspect} must use a closed Draft 2020-12 object schema"
            )
          end

          mapping = contribution.send(
            :normalize_mapping,
            schema.fetch("properties"),
            label: "plugin job #{key.inspect} argument properties"
          )
          if mapping.length > MAX_ARGUMENTS
            contribution.send(:schema_error!, "plugin job #{key.inspect} has too many arguments")
          end
          properties = mapping.sort.to_h do |argument_key, attributes|
            property = Property.new(
              contribution:,
              key: argument_key,
              attributes:
            )
            [ property.key, property ]
          end.freeze

          required = schema.fetch("required", [])
          unless required.is_a?(Array)
            contribution.send(:schema_error!, "plugin job #{key.inspect} required must be an array")
          end
          normalized_required = required.map {
            |argument_key| contribution.send(:normalize_argument_key, argument_key)
          }
          if normalized_required.uniq.length != normalized_required.length
            contribution.send(
              :schema_error!,
              "plugin job #{key.inspect} required arguments must be unique"
            )
          end
          unknown = normalized_required - properties.keys
          if unknown.any?
            contribution.send(
              :schema_error!,
              "plugin job #{key.inspect} requires unknown arguments: #{unknown.sort.join(', ')}"
            )
          end
          [ properties, normalized_required.sort.freeze ]
        end

        def bounded_integer(contribution, value, key:, range:)
          unless value.is_a?(Integer) && range.cover?(value)
            contribution.send(
              :schema_error!,
              "plugin job #{self.key.inspect} #{key} must be within #{range}"
            )
          end
          value
        end

        def canonical_hash
          {
            "plugin_id" => plugin_id,
            "key" => key,
            "properties" => properties.transform_values(&:to_h),
            "required" => required_keys,
            "max_attempts" => max_attempts,
            "retry_wait_seconds" => retry_wait_seconds,
            "lease_seconds" => lease_seconds
          }
        end

        def deep_freeze(value)
          case value
          when Hash
            value.each { |item_key, item| deep_freeze(item_key); deep_freeze(item) }
          when Array
            value.each { |item| deep_freeze(item) }
          end
          value.freeze
        end
      end

      attr_reader :plugin_id, :version, :jobs, :digest

      def initialize(plugin_id:, document:)
        @plugin_id = plugin_id.to_s.dup.freeze
        root = normalize_mapping(
          document,
          label: "jobs contribution root",
          allowed: ROOT_KEYS
        )
        missing = ROOT_KEYS - root.keys
        schema_error!("jobs contribution is missing: #{missing.join(', ')}") if missing.any?
        @version = normalize_version(root.fetch("schema_version"))
        job_mapping = normalize_mapping(root.fetch("jobs"), label: "jobs contribution")
        schema_error!("jobs contribution must declare at least one job") if job_mapping.empty?
        schema_error!("jobs contribution has too many jobs") if job_mapping.length > MAX_JOBS
        @jobs = job_mapping.sort.to_h do |job_key, attributes|
          definition = Definition.new(contribution: self, key: job_key, attributes:)
          [ definition.key, definition ]
        end.freeze
        @digest = Digest::SHA256.hexdigest(
          JSON.generate(
            {
              "plugin_id" => plugin_id,
              "schema_version" => version,
              "jobs" => jobs.transform_values(&:to_h)
            }
          )
        ).freeze
        freeze
      end

      def fetch(job_key)
        jobs[job_key.to_s] || raise(
          JobValidationError.new(
            code: "job_not_declared",
            message: "plugin job is not declared by this plugin"
          )
        )
      end

      def to_h
        {
          "plugin_id" => plugin_id,
          "schema_version" => version,
          "digest" => digest,
          "jobs" => jobs.values.sort_by(&:key).map(&:to_h)
        }.freeze
      end

      private

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

      def normalize_version(value)
        unless value.is_a?(String) && value.length <= 32 && value.match?(VERSION_PATTERN)
          schema_error!("jobs contribution schema_version must be a positive integer string")
        end
        value.dup.freeze
      end

      def normalize_job_key(value)
        normalize_key(value, label: "job", pattern: JOB_KEY_PATTERN)
      end

      def normalize_argument_key(value)
        normalize_key(value, label: "job argument", pattern: ARGUMENT_KEY_PATTERN)
      end

      def normalize_key(value, label:, pattern:)
        unless value.is_a?(String) || value.is_a?(Symbol)
          schema_error!("#{label} keys must be strings")
        end
        key = value.to_s
        unless key.length.between?(1, MAX_KEY_LENGTH) && key.match?(pattern)
          schema_error!("invalid #{label} key #{key.inspect}")
        end
        key.freeze
      end

      def required_string(data, key, label:)
        value = data[key]
        unless value.is_a?(String) && value.present?
          schema_error!("#{label} #{key} must be a non-empty string")
        end
        value.dup.freeze
      end

      def json_scalar?(value)
        value == true || value == false || value.is_a?(String) ||
          value.is_a?(Integer) || (value.is_a?(Float) && value.finite?)
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

    class JobContributionLoader
      MAX_FILE_BYTES = 1_048_576

      def self.load(manifest)
        new(manifest).load
      end

      def initialize(manifest)
        @manifest = manifest
      end

      def load
        relative_path = @manifest.jobs_contribution_path
        return unless relative_path
        unless @manifest.source_path
          raise ManifestError, "jobs contribution requires a file-backed manifest"
        end

        source = resolve_source(relative_path)
        yaml = read_yaml(source)
        parsed = YAML.safe_load(
          yaml,
          permitted_classes: [],
          permitted_symbols: [],
          aliases: false
        )
        JobContribution.new(plugin_id: @manifest.id, document: parsed)
      rescue Psych::Exception => e
        raise ManifestError, "invalid safe jobs contribution YAML: #{e.message}"
      rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP => e
        raise ManifestError, "invalid jobs contribution file: #{e.message}"
      end

      private

      def resolve_source(relative_path)
        root = Pathname(@manifest.source_path).dirname.realpath
        candidate = root.join(relative_path).cleanpath
        unless candidate.file?
          raise ManifestError, "jobs contribution does not exist: #{candidate}"
        end

        candidate_real = candidate.realpath
        unless contained_path?(candidate_real, root)
          raise ManifestError, "jobs contribution must remain inside the plugin directory"
        end
        candidate_real
      end

      def read_yaml(source)
        yaml = File.open(source, "rb") { |file| file.read(MAX_FILE_BYTES + 1) }
        raise ManifestError, "jobs contribution is too large" if yaml.bytesize > MAX_FILE_BYTES

        yaml.force_encoding(Encoding::UTF_8)
        raise ManifestError, "jobs contribution must be valid UTF-8" unless yaml.valid_encoding?

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
              raise ManifestError, "jobs contribution mapping keys must be scalar strings"
            end
            normalized_key = key.value.to_s
            if seen.key?(normalized_key)
              raise ManifestError, "duplicate jobs contribution key #{normalized_key.inspect}"
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
