# frozen_string_literal: true

module Operations
  module CoreDurableEnqueueHandlers
    module_function

    def register(registry)
      registry.register(
        key: Identity::EmailVerificationDelivery::HANDLER_KEY,
        source_kind: "user",
        queue: "mailers",
        replay_contract: "at_least_once",
        lease: 5.minutes,
        max_attempts: 5,
        retry_delays: [ 1.minute, 5.minutes, 30.minutes, 2.hours ],
        argument_schema: {
          "token_digest" => {
            type: "string",
            required: true,
            maximum: 64,
            pattern: /\A[0-9a-f]{64}\z/
          }
        }
      ) do |intent, _context|
        Identity::EmailVerificationDelivery.deliver(intent)
      end

      registry.register(
        key: "community.web_push",
        source_kind: "notification",
        queue: "default",
        replay_contract: "at_least_once",
        lease: 5.minutes,
        max_attempts: 5,
        retry_delays: [ 1.minute, 5.minutes, 30.minutes, 2.hours ]
      ) do |intent, context|
        result = Community::DeliverWebPushForNotification.call(
          notification_id: intent.source_id,
          delivery_key: context.idempotency_key
        )
        unless result.success?
          raise Operations::DurableEnqueueCatalog::ExecutionError,
                result.code.presence || "web_push_delivery_failed"
        end

        value = result.value.to_h.symbolize_keys
        if value[:skipped]
          Operations::DurableEnqueueResult.skipped(
            error_code: value[:reason_code].presence || "delivery_skipped"
          )
        else
          Operations::DurableEnqueueResult.succeeded
        end
      end
    end
  end
end
