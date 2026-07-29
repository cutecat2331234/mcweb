# frozen_string_literal: true

module Commerce
  module Disputes
    class PurgeEvidence < ApplicationService
      def initialize(evidence:, at: Time.current)
        @evidence = evidence
        @at = at
      end

      def call
        result = nil

        Commerce::DisputeEvidence.transaction do
          evidence = Commerce::DisputeEvidence.lock.find(@evidence.id)
          dispute = Commerce::Dispute.lock.find(evidence.store_dispute_id)
          if evidence.purged?
            result = ServiceResult.success(evidence: evidence, idempotent: true)
            next
          end
          unless dispute.purge_allowed?(at: @at) &&
              evidence.retention_until.present? &&
              evidence.retention_until <= @at
            result = ServiceResult.failure(
              error: "dispute_retention_blocked",
              value: { blockers: dispute.retention_blockers(at: @at) }
            )
            next
          end

          evidence.update!(
            content: nil,
            byte_size: 0,
            sha256: Digest::SHA256.hexdigest(""),
            submission_status: "purged",
            purged_at: @at
          )
          event = Commerce::DisputeEvent.create!(
            dispute: dispute,
            idempotency_key: "dispute-evidence-purge:#{evidence.id}",
            source: "system",
            event_type: "evidence_purged",
            from_status: dispute.status,
            to_status: dispute.status,
            metadata: {
              "evidence_public_id" => evidence.public_id,
              "retention_until" => evidence.retention_until.iso8601(6)
            }
          )
          Administration::AuditLogger.call(
            action: "commerce.dispute_evidence_purged",
            resource: dispute,
            before_state: { evidence_available: true },
            after_state: { evidence_available: false },
            metadata: {
              dispute_event_id: event.id,
              evidence_public_id: evidence.public_id
            }
          )
          result = ServiceResult.success(evidence: evidence, idempotent: false)
        end

        result
      rescue ActiveRecord::RecordNotUnique
        ServiceResult.success(evidence: @evidence.reload, idempotent: true)
      rescue ActiveRecord::RecordInvalid => error
        ServiceResult.failure(errors: error.record.errors.to_hash)
      end
    end
  end
end
