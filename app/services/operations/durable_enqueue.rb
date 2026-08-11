# frozen_string_literal: true

require "digest"

module Operations
  module DurableEnqueue
    class TransactionRequired < StandardError; end
    class InvalidRequest < StandardError; end
    class IdempotencyConflict < StandardError; end

    DEDUPE_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9._:\/-]*\z/

    module_function

    def record!(handler:, source_id:, dedupe_key:, arguments: {}, requested_at: Time.current)
      ensure_transaction!
      entry = Operations::DurableEnqueueCatalog.entry(handler)
      raise InvalidRequest, "durable_enqueue_handler_unknown" unless entry

      normalized_source_id = Integer(source_id, exception: false)
      normalized_dedupe_key = dedupe_key.to_s
      unless normalized_source_id&.positive? &&
          normalized_dedupe_key.length.between?(1, 191) &&
          normalized_dedupe_key.match?(DEDUPE_PATTERN)
        raise InvalidRequest, "durable_enqueue_request_invalid"
      end

      normalized_arguments = Operations::DurableEnqueueCatalog.normalize_arguments(entry, arguments)
      fingerprint = request_fingerprint(
        entry:,
        source_id: normalized_source_id,
        arguments: normalized_arguments
      )
      intent = nil
      created = false

      Operations::DurableEnqueueIntent.transaction(requires_new: true) do
        intent = Operations::DurableEnqueueIntent.lock.find_by(
          handler_key: entry.key,
          dedupe_key: normalized_dedupe_key
        )
        if intent
          verify_replay!(intent, entry:, source_id: normalized_source_id, fingerprint:)
        else
          intent = Operations::DurableEnqueueIntent.create!(
            handler_key: entry.key,
            source_kind: entry.source_kind,
            source_id: normalized_source_id,
            dedupe_key: normalized_dedupe_key,
            queue_name: entry.queue_name,
            arguments: normalized_arguments,
            arguments_sha256: fingerprint,
            requested_at:
          )
          Operations::DurableEnqueueLedger.append!(
            intent:,
            event_type: "recorded",
            generation: 1,
            occurred_at: requested_at
          )
          created = true
        end
      end

      enqueue_after_commit(intent.id, generation: 1) if created
      intent
    rescue ActiveRecord::RecordNotUnique
      intent = Operations::DurableEnqueueIntent.find_by!(
        handler_key: entry.key,
        dedupe_key: normalized_dedupe_key
      )
      verify_replay!(intent, entry:, source_id: normalized_source_id, fingerprint:)
      intent
    end

    def ensure_transaction!
      return if ApplicationRecord.connection.transaction_open?

      raise TransactionRequired, "durable enqueue intents require an open business transaction"
    end
    private_class_method :ensure_transaction!

    def request_fingerprint(entry:, source_id:, arguments:)
      Digest::SHA256.hexdigest(
        ActiveSupport::JSON.encode(
          {
            handler_key: entry.key,
            source_kind: entry.source_kind,
            source_id:,
            queue_name: entry.queue_name,
            arguments:
          }
        )
      )
    end
    private_class_method :request_fingerprint

    def verify_replay!(intent, entry:, source_id:, fingerprint:)
      return if intent.source_kind == entry.source_kind &&
        intent.source_id == source_id &&
        intent.queue_name == entry.queue_name &&
        intent.arguments_sha256 == fingerprint

      raise IdempotencyConflict, "durable_enqueue_idempotency_conflict"
    end
    private_class_method :verify_replay!

    def enqueue_after_commit(intent_id, generation:)
      ActiveRecord.after_all_transactions_commit do
        Operations::DurableEnqueueDispatcher.call(
          intent_id:,
          generation:,
          trigger: "after_commit"
        )
      end
    end
    private_class_method :enqueue_after_commit
  end
end
