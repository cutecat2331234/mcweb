# frozen_string_literal: true

module Payments
  class CompleteFakePaymentJob < ApplicationJob
    queue_as :default

    def perform(payment_record_id)
      payment = Payments::Record.find_by(id: payment_record_id)
      return unless payment&.provider == "fake"
      return unless payment.pending? || payment.processing?
      return unless payment.metadata.to_h["developer_mode_scenario"] == "delayed"

      scheduled_for = Time.iso8601(
        payment.metadata.to_h.fetch("developer_mode_scheduled_for")
      )
      return if scheduled_for.future?

      unless Mcweb::DeveloperMode.enabled? &&
          Mcweb::DeveloperMode.integration(:payments) == :fake
        AuditLog.record!(
          action: "developer_mode.fake_payment_delayed_skipped",
          resource: payment,
          metadata: { reason: "developer_mode_disabled" }
        )
        return
      end

      result = Commerce::ConfirmPayment.call(
        payment_record: payment,
        provider_payment_id: payment.provider_payment_id
      )
      AuditLog.record!(
        action: result.success? ?
          "developer_mode.fake_payment_delayed_completed" :
          "developer_mode.fake_payment_delayed_failed",
        resource: payment,
        metadata: {
          result_code: result.success? ? "success" : result.code.to_s
        }
      )
    rescue ArgumentError, KeyError
      AuditLog.record!(
        action: "developer_mode.fake_payment_delayed_skipped",
        resource: payment,
        metadata: { reason: "invalid_schedule" }
      ) if payment
    end
  end
end
