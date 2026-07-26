# frozen_string_literal: true

module Payments
  class StripeFinancialHistory
    PROVIDER = "stripe"

    class << self
      def exists?
        payment_history? ||
          financial_webhook_history? ||
          reconciliation_observation_history? ||
          reconciliation_discrepancy_history?
      end

      private

      def payment_history?
        table_exists?(Payments::Record) &&
          Payments::Record.where(provider: PROVIDER).exists?
      end

      def financial_webhook_history?
        return false unless table_exists?(Payments::WebhookEvent)

        Payments::WebhookEvent
          .where(provider: PROVIDER)
          .where(
            "event_type LIKE :checkout OR event_type LIKE :payment " \
              "OR event_type LIKE :charge OR event_type LIKE :refund",
            checkout: "checkout.session.%",
            payment: "payment_intent.%",
            charge: "charge.%",
            refund: "refund.%"
          )
          .exists?
      end

      def reconciliation_observation_history?
        return false unless table_exists?(Payments::ReconciliationObservation)
        return false unless table_exists?(Payments::ReconciliationRun)

        Payments::ReconciliationObservation
          .joins(:run)
          .where(payment_reconciliation_runs: { provider: PROVIDER })
          .exists?
      end

      def reconciliation_discrepancy_history?
        table_exists?(Payments::ReconciliationDiscrepancy) &&
          Payments::ReconciliationDiscrepancy.where(provider: PROVIDER).exists?
      end

      def table_exists?(model)
        ActiveRecord::Base.connection.data_source_exists?(model.table_name)
      end
    end
  end
end
