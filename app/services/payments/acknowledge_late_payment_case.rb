# frozen_string_literal: true

module Payments
  class AcknowledgeLatePaymentCase < ApplicationService
    MIN_NOTE_LENGTH = 10
    MAX_NOTE_LENGTH = 1_000

    def initialize(review_case:, actor:, token:, confirmation:, disposition:, note:,
                   ip_address: nil, user_agent: nil)
      @review_case = review_case
      @actor = actor
      @token = token
      @confirmation = confirmation.to_s.strip
      @disposition = disposition.to_s
      @note = note.to_s.strip
      @ip_address = ip_address
      @user_agent = user_agent.to_s.first(500).presence
    end

    def call
      return forbidden_result unless @actor&.permission?(Payments::LatePaymentCase::PERMISSION)
      return invalid_input_result unless valid_input?

      acknowledged_case = nil
      idempotent = false

      Payments::LatePaymentCase.transaction do
        review_case = Payments::LatePaymentCase.lock.find(@review_case.id)

        unless Payments::LatePaymentReviewToken.valid?(@token, review_case)
          return ServiceResult.failure(
            error: :late_payment_review_authorization_expired_or_is_invalid,
            code: "invalid_review_token"
          )
        end

        unless secure_confirmation_match?(review_case.order.order_number)
          return ServiceResult.failure(
            error: :enter_the_exact_order_number_to_confirm_this_review,
            code: "confirmation_mismatch"
          )
        end

        if review_case.acknowledged?
          if same_acknowledgement?(review_case)
            acknowledged_case = review_case
            idempotent = true
            next
          end

          return ServiceResult.failure(
            error: :this_late_payment_was_already_acknowledged_with_different_review_details,
            code: "already_acknowledged"
          )
        end

        before_state = {
          status: review_case.status,
          disposition: review_case.disposition
        }
        review_case.update!(
          status: "acknowledged",
          disposition: @disposition,
          review_note: @note,
          acknowledged_by: @actor,
          acknowledged_at: Time.current
        )

        Administration::AuditLogger.call(
          actor: @actor,
          action: "admin.payment_late_payment_acknowledged",
          resource: review_case,
          reason: @note,
          ip_address: @ip_address,
          user_agent: @user_agent,
          metadata: {
            provider: review_case.provider,
            reason: review_case.reason,
            disposition: review_case.disposition,
            payment_record_id: review_case.payment_record_id,
            payment_webhook_event_id: review_case.payment_webhook_event_id,
            order_public_id: review_case.order.public_id
          },
          before_state: before_state,
          after_state: {
            status: review_case.status,
            disposition: review_case.disposition,
            acknowledged_by_id: @actor.id
          }
        )
        acknowledged_case = review_case
      end

      ServiceResult.success(review_case: acknowledged_case, idempotent: idempotent)
    end

    private

    def valid_input?
      @disposition.in?(Payments::LatePaymentCase::DISPOSITIONS) &&
        @note.length.between?(MIN_NOTE_LENGTH, MAX_NOTE_LENGTH)
    end

    def invalid_input_result
      ServiceResult.failure(
        error: I18n.t(
          "mcweb.user_copy.late_payment_review_input_invalid",
          min: MIN_NOTE_LENGTH,
          max: MAX_NOTE_LENGTH
        ),
        code: "invalid_review_details"
      )
    end

    def forbidden_result
      ServiceResult.failure(
        error: :you_do_not_have_permission_to_review_late_payments,
        code: "forbidden"
      )
    end

    def secure_confirmation_match?(order_number)
      expected = order_number.to_s
      @confirmation.bytesize == expected.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(@confirmation, expected)
    end

    def same_acknowledgement?(review_case)
      review_case.acknowledged_by_id == @actor.id &&
        review_case.disposition == @disposition &&
        review_case.review_note == @note
    end
  end
end
