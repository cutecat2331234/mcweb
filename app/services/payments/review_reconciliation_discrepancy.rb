# frozen_string_literal: true

module Payments
  class ReviewReconciliationDiscrepancy < ApplicationService
    DECISIONS = %w[acknowledge ignore].freeze
    STATUS_BY_DECISION = {
      "acknowledge" => "acknowledged",
      "ignore" => "ignored"
    }.freeze
    MIN_NOTE_LENGTH = 10
    MAX_NOTE_LENGTH = 1_000

    def initialize(discrepancy:, actor:, token:, confirmation:, decision:, note:,
                   ip_address: nil, user_agent: nil)
      @discrepancy = discrepancy
      @actor = actor
      @token = token
      @confirmation = confirmation.to_s.strip
      @decision = decision.to_s
      @note = note.to_s.gsub(/[[:cntrl:]]/, " ").squish
      @ip_address = ip_address
      @user_agent = user_agent.to_s.first(500).presence
    end

    def call
      return forbidden_result unless @actor&.permission?(
        Payments::ReconciliationDiscrepancy::REVIEW_PERMISSION
      )
      return invalid_input_result unless valid_input?

      reviewed = nil
      idempotent = false

      Payments::ReconciliationDiscrepancy.transaction do
        discrepancy = Payments::ReconciliationDiscrepancy.lock.find(@discrepancy.id)
        unless Payments::ReconciliationReviewToken.valid?(@token, discrepancy)
          return ServiceResult.failure(
            error: "Reconciliation review authorization expired or is invalid.",
            code: "invalid_review_token"
          )
        end
        unless secure_confirmation_match?(discrepancy.public_id)
          return ServiceResult.failure(
            error: "Enter the exact discrepancy ID to confirm this review.",
            code: "confirmation_mismatch"
          )
        end

        target_status = STATUS_BY_DECISION.fetch(@decision)
        unless discrepancy.open?
          if same_review?(discrepancy, target_status)
            reviewed = discrepancy
            idempotent = true
            next
          end

          return ServiceResult.failure(
            error: "This discrepancy was already reviewed with different details.",
            code: "already_reviewed"
          )
        end

        before_state = { status: discrepancy.status }
        discrepancy.update!(
          status: target_status,
          review_note: @note,
          reviewed_by: @actor,
          reviewed_at: Time.current
        )

        Administration::AuditLogger.call(
          actor: @actor,
          action: "admin.payment_reconciliation_discrepancy_reviewed",
          resource: discrepancy,
          reason: @note,
          ip_address: @ip_address,
          user_agent: @user_agent,
          metadata: {
            provider: discrepancy.provider,
            mode: discrepancy.mode,
            subject_type: discrepancy.subject_type,
            kind: discrepancy.kind,
            decision: @decision,
            reconciliation_run_id: discrepancy.run_id,
            payment_record_id: discrepancy.payment_record_id,
            refund_id: discrepancy.refund_id,
            order_public_id: discrepancy.order&.public_id
          }.compact,
          before_state: before_state,
          after_state: {
            status: discrepancy.status,
            reviewed_by_id: @actor.id
          }
        )
        reviewed = discrepancy
      end

      ServiceResult.success(discrepancy: reviewed, idempotent: idempotent)
    end

    private

    def valid_input?
      @decision.in?(DECISIONS) &&
        @note.length.between?(MIN_NOTE_LENGTH, MAX_NOTE_LENGTH)
    end

    def invalid_input_result
      ServiceResult.failure(
        error: "Select a valid decision and enter a note between " \
          "#{MIN_NOTE_LENGTH} and #{MAX_NOTE_LENGTH} characters.",
        code: "invalid_review_details"
      )
    end

    def forbidden_result
      ServiceResult.failure(
        error: "You do not have permission to review reconciliation discrepancies.",
        code: "forbidden"
      )
    end

    def secure_confirmation_match?(expected)
      expected = expected.to_s
      @confirmation.bytesize == expected.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(@confirmation, expected)
    end

    def same_review?(discrepancy, target_status)
      discrepancy.status == target_status &&
        discrepancy.reviewed_by_id == @actor.id &&
        discrepancy.review_note == @note
    end
  end
end
