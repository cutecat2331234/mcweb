# frozen_string_literal: true

require Rails.root.join("lib/mcweb/operations_manual_task_registrar_config")

module Operations
  class ManualTaskCatalog
    class InvalidTask < StandardError; end

    class ExecutionError < StandardError
      attr_reader :code

      def initialize(code, message = nil)
        @code = code.to_s
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

        entry.argument_schema.each_with_object({}) do |(key, schema), normalized|
          value = source[key]
          if value.blank?
            raise InvalidTask, "#{key}_required" if schema[:required]
            next
          end

          normalized[key] = normalize_argument(key, value, schema)
        end
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
        else
          raise InvalidTask, "argument_schema_invalid"
        end
      end
    end
  end
end
