# frozen_string_literal: true

module Operations
  class DurableEnqueueAdmission
    ERROR_CODE = "background_processing_unavailable"

    class Unavailable < StandardError; end

    class << self
      def record!(**attributes)
        Operations::DurableEnqueue.record!(**attributes)
      rescue Operations::DurableEnqueue::TransactionRequired,
             Operations::DurableEnqueue::InvalidRequest,
             Operations::DurableEnqueue::IdempotencyConflict,
             Operations::DurableEnqueueLedger::InvalidTransition,
             ActiveRecord::ActiveRecordError,
             ArgumentError,
             FrozenError => error
        Rails.logger.error(
          "[operations.durable_enqueue] admission_failed " \
          "handler=#{attributes[:handler]} error=#{error.class.name}"
        )
        raise Unavailable, ERROR_CODE
      end
    end
  end
end
