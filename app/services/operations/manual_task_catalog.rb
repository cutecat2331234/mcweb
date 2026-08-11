# frozen_string_literal: true

require Rails.root.join("lib/mcweb/operations_manual_task_registrar_config")

module Operations
  class ManualTaskCatalog
    class InvalidTask < StandardError; end

    class ExecutionError < StandardError
      attr_reader :code, :result

      def initialize(code, message = nil, result: {})
        @code = code.to_s
        @result = result.to_h.deep_stringify_keys
        super(message || @code)
      end
    end

    class << self
      def entry(key)
        registry.entry(key)
      end

      def entries
        registry.entries
      end

      def entries_for(actor)
        registry.entries.select { |candidate| allowed?(actor, candidate) }
      end

      def allowed?(actor, entry)
        actor.present? && entry.permissions.all? { |permission| actor.permission?(permission) }
      end

      def execute(run)
        candidate = entry(run.task_key)
        raise InvalidTask, "manual_task_unknown" unless candidate

        candidate.executor.call(run)
      end

      def normalize_arguments(entry, raw_arguments)
        source = raw_arguments.to_h.stringify_keys
        unknown = source.keys - entry.argument_schema.keys
        raise InvalidTask, "unsupported_arguments" if unknown.any?

        normalized = entry.argument_schema.each_with_object({}) do |(key, schema), result|
          value = source[key]
          if value.blank?
            raise InvalidTask, "#{key}_required" if schema[:required]
            next
          end

          result[key] = normalize_argument(key, value, schema)
        end
        if ActiveSupport::JSON.encode(normalized).bytesize > Operations::ManualTaskRegistry::MAX_ARGUMENT_BYTES
          raise InvalidTask, "manual_task_arguments_too_large"
        end
        normalized
      end

      def registry_frozen?
        registry.frozen?
      end

      def reset_registry!
        @registry = nil
      end

      private

      def registry
        @registry ||= begin
          candidate = Operations::ManualTaskRegistry.new
          Operations::MinecraftManualTasks.register(candidate)
          Operations::DurableEnqueueManualTasks.register(candidate)
          configured_registrars.each { |registrar| registrar.call(candidate) }
          candidate.freeze!
        end
      end

      def configured_registrars
        Mcweb::OperationsManualTaskRegistrarConfig.freeze_and_fetch!(
          Rails.application.config.x
        )
      end

      def normalize_argument(key, value, schema)
        case schema.fetch(:type)
        when "integer"
          integer = Integer(value, exception: false)
          minimum = schema[:minimum]
          if integer.nil? || (minimum && integer < minimum)
            raise InvalidTask, "#{key}_invalid"
          end
          integer
        when "integer_list"
          values = value.is_a?(Array) ? value : value.to_s.split(/[\s,]+/)
          parsed = values.reject { |entry| entry.to_s.blank? }
                         .map { |entry| Integer(entry, exception: false) }
          integers = parsed.compact.uniq
          minimum = schema[:minimum]
          invalid = integers.empty? || parsed.any?(&:nil?)
          invalid ||= minimum && integers.any? { |entry| entry < minimum }
          invalid ||= schema[:maximum_items] && integers.length > schema[:maximum_items]
          raise InvalidTask, "#{key}_invalid" if invalid

          integers
        when "string"
          string = value.to_s.strip
          maximum = schema[:maximum]
          raise InvalidTask, "#{key}_invalid" if string.blank? || (maximum && string.length > maximum)

          string
        when "uuid_list"
          values = value.is_a?(Array) ? value : value.to_s.split(/[\s,]+/)
          parsed = values.reject { |entry| entry.to_s.blank? }.map(&:to_s)
          uuids = parsed.select do |entry|
            entry.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i)
          end.map(&:downcase).uniq
          invalid = uuids.empty? || uuids.length != parsed.length
          invalid ||= schema[:maximum_items] && uuids.length > schema[:maximum_items]
          raise InvalidTask, "#{key}_invalid" if invalid

          uuids
        else
          raise InvalidTask, "argument_schema_invalid"
        end
      end
    end
  end
end
