# frozen_string_literal: true

require Rails.root.join("lib/mcweb/operations_durable_enqueue_registrar_config")

module Operations
  class DurableEnqueueCatalog
    class InvalidHandler < StandardError; end

    class ExecutionError < StandardError
      attr_reader :code

      def initialize(code, message = nil)
        @code = code.to_s
        super(message || @code)
      end
    end

    class << self
      def entry(key)
        ensure_finalized!
        registry.entry(key)
      end

      def entries
        ensure_finalized!
        registry.entries
      end

      def normalize_arguments(entry, arguments)
        ensure_finalized!
        registry.normalize_arguments(entry, arguments)
      end

      def execute(intent, context:)
        candidate = entry(intent.handler_key)
        raise InvalidHandler, "durable_enqueue_handler_unknown" unless candidate
        unless intent.source_kind == candidate.source_kind && intent.queue_name == candidate.queue_name
          raise InvalidHandler, "durable_enqueue_handler_snapshot_mismatch"
        end

        result = candidate.executor.call(intent, context)
        unless result.is_a?(Operations::DurableEnqueueResult)
          raise ExecutionError, "durable_enqueue_result_invalid"
        end
        result
      end

      def finalize!
        @registry ||= build_registry
        @boot_finalized = true
        @registry
      end

      def registry_frozen?
        @boot_finalized == true && @registry&.frozen? == true
      end

      private

      def registry
        ensure_finalized!
        @registry
      end

      def ensure_finalized!
        return if @boot_finalized == true

        raise FrozenError, "durable_enqueue_registry_not_boot_finalized"
      end

      def build_registry
        candidate = Operations::DurableEnqueueRegistry.new
        Operations::CoreDurableEnqueueHandlers.register(candidate)
        configured_registrars.each { |registrar| registrar.call(candidate) }
        candidate.freeze!
      end

      def configured_registrars
        Mcweb::OperationsDurableEnqueueRegistrarConfig.freeze_and_fetch!(
          Rails.application.config.x
        )
      end
    end
  end
end
