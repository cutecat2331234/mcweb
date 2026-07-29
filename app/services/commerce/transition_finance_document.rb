# frozen_string_literal: true

module Commerce
  class TransitionFinanceDocument < ApplicationService
    PERMISSION = "store.finance.documents.manage"
    ACTIONS = %w[revise void].freeze
    UUID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

    def initialize(document:, actor:, action:, reason:, request_id:, ip_address: nil, user_agent: nil)
      @document = document
      @actor = actor
      @action = action.to_s
      @reason = reason.to_s.strip
      @request_id = request_id.to_s.strip.downcase
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      validation = validation_failure
      return validation if validation

      result_document = nil
      replayed = false

      FinanceDocument.transaction do
        existing_event = FinanceDocumentEvent.find_by(request_id: @request_id)
        if existing_event
          return failure("finance_document_idempotency_conflict") unless event_matches?(existing_event)

          result_document = replay_document(existing_event)
          replayed = true
          next
        end

        document = FinanceDocument.lock.find(@document.id)
        return failure("finance_document_transition_not_allowed") unless document.issued?

        result_document = @action == "void" ? void_document!(document) : revise_document!(document)
      end

      ServiceResult.success(document: result_document, replayed:)
    rescue ActiveRecord::RecordNotUnique
      event = FinanceDocumentEvent.find_by!(request_id: @request_id)
      return failure("finance_document_idempotency_conflict") unless event_matches?(event)

      ServiceResult.success(document: replay_document(event), replayed: true)
    rescue ActiveRecord::StaleObjectError
      failure("finance_document_conflict")
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash, code: "finance_document_invalid")
    end

    private

    def validation_failure
      return failure("finance_document_unauthorized") unless @actor&.permission?(PERMISSION)
      return failure("finance_document_action_invalid") unless ACTIONS.include?(@action)
      return failure("finance_document_reason_required") if @reason.length < 10 || @reason.length > 1_000
      return failure("finance_document_request_id_invalid") unless @request_id.match?(UUID_FORMAT)

      nil
    end

    def void_document!(document)
      before = state(document)
      document.update!(status: "voided", voided_at: Time.current)
      after = state(document)
      document.events.create!(
        actor: @actor,
        event_type: "voided",
        request_id: @request_id,
        reason: @reason,
        before_state: before,
        after_state: after,
        metadata: { transition_action: @action },
        created_at: Time.current
      )
      audit_transition!(document, before, after)
      document
    end

    def revise_document!(document)
      before = state(document)
      document.update!(status: "superseded", superseded_at: Time.current)
      revised = FinanceDocument.create!(
        document.attributes.symbolize_keys.slice(
          :store_order_id,
          :store_refund_id,
          :store_finance_tax_snapshot_id,
          :document_kind,
          :document_number,
          :channel,
          :currency,
          :net_amount_cents,
          :tax_amount_cents,
          :gross_amount_cents,
          :source_digest,
          :retention_until
        ).merge(
          supersedes: document,
          version: document.version + 1,
          status: "issued",
          content_snapshot: document.content_snapshot.merge(
            "revision_reason" => @reason,
            "revision_request_id" => @request_id
          ),
          issued_at: Time.current
        )
      )
      after = state(revised)
      document.events.create!(
        actor: @actor,
        event_type: "superseded",
        request_id: @request_id,
        reason: @reason,
        before_state: before,
        after_state: after,
        metadata: {
          transition_action: @action,
          replacement_public_id: revised.public_id,
          replacement_version: revised.version
        },
        created_at: Time.current
      )
      revised.events.create!(
        actor: @actor,
        event_type: "issued",
        reason: @reason,
        after_state: after,
        metadata: {
          previous_public_id: document.public_id,
          revision_request_id: @request_id
        },
        created_at: Time.current
      )
      audit_transition!(revised, before, after)
      revised
    end

    def audit_transition!(resource, before, after)
      Administration::AuditLogger.call(
        actor: @actor,
        action: @action == "void" ?
          "commerce.finance_document_voided" :
          "commerce.finance_document_revised",
        resource:,
        request_id: @request_id,
        reason: @reason,
        before_state: before,
        after_state: after,
        metadata: {
          original_document_public_id: @document.public_id,
          document_number: resource.document_number,
          version: resource.version
        },
        ip_address: @ip_address,
        user_agent: @user_agent
      )
    end

    def event_matches?(event)
      event.store_finance_document_id == @document.id &&
        event.metadata["transition_action"] == @action
    end

    def replay_document(event)
      replacement_id = event.metadata["replacement_public_id"]
      return event.finance_document if replacement_id.blank?

      FinanceDocument.find_by!(public_id: replacement_id)
    end

    def state(document)
      {
        public_id: document.public_id,
        status: document.status,
        document_number: document.document_number,
        version: document.version,
        net_amount_cents: document.net_amount_cents,
        tax_amount_cents: document.tax_amount_cents,
        gross_amount_cents: document.gross_amount_cents
      }
    end

    def failure(code)
      ServiceResult.failure(error: code, code:)
    end
  end
end
