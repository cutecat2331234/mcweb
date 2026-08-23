# frozen_string_literal: true

module Minecraft
  module NodeOperationPreparation
    HANDLER_KEY = "minecraft.node_operation_preparation"

    module_function

    def register(registry)
      registry.register(
        key: HANDLER_KEY,
        source_kind: "minecraft.node_operation",
        queue: "minecraft",
        replay_contract: "idempotent",
        enqueue_stale_after: 30.seconds,
        lease: 5.minutes,
        heartbeat: 30.seconds,
        max_attempts: 10,
        retry_delays: [
          1.minute,
          5.minutes,
          15.minutes,
          30.minutes,
          1.hour,
          2.hours,
          4.hours,
          8.hours,
          12.hours
        ]
      ) do |intent, _context|
        execute(intent)
      end
    end

    def record!(operation:)
      Operations::DurableEnqueueAdmission.record!(
        handler: HANDLER_KEY,
        source_id: operation.id,
        dedupe_key: "minecraft-node-operation:#{operation.public_id}"
      )
    end

    def execute(intent)
      operation = Minecraft::NodeOperation.find_by(id: intent.source_id)
      return skipped("source_missing") unless operation
      return skipped("node_operation_terminal") if operation.terminal?
      return Operations::DurableEnqueueResult.succeeded unless operation.status_queued?

      Minecraft::PrepareNodeOperationJob.perform_now
      operation.reload
      return Operations::DurableEnqueueResult.succeeded unless operation.status_queued?

      raise Operations::DurableEnqueueCatalog::ExecutionError,
        "node_operation_dispatch_deferred"
    end

    def skipped(code)
      Operations::DurableEnqueueResult.skipped(error_code: code)
    end
    private_class_method :skipped
  end
end
