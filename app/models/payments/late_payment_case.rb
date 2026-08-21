# frozen_string_literal: true

module Payments
  class LatePaymentCase < ApplicationRecord
    PERMISSION = "store.payments.late_review"
    REASONS = Commerce::ConfirmPayment::ORPHAN_REASONS
    DISPOSITIONS = %w[
      refund_required
      contact_customer
      duplicate_payment
      no_action_required
      other
    ].freeze

    belongs_to :payment_record, class_name: "Payments::Record"
    belongs_to :webhook_event,
      class_name: "Payments::WebhookEvent",
      foreign_key: :payment_webhook_event_id
    belongs_to :order, class_name: "Commerce::Order", foreign_key: :store_order_id
    belongs_to :acknowledged_by, class_name: "User", optional: true

    attr_readonly :payment_record_id,
      :payment_webhook_event_id,
      :store_order_id,
      :provider,
      :reason,
      :amount_cents,
      :currency

    enum :status, {
      open: "open",
      acknowledged: "acknowledged"
    }, validate: true

    validates :provider, :currency, presence: true
    validates :reason, inclusion: { in: REASONS }
    validates :disposition, inclusion: { in: DISPOSITIONS }, allow_nil: true
    validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :payment_record_id, uniqueness: true
    validates :payment_webhook_event_id, uniqueness: true
    validate :associations_match
    validate :acknowledgement_is_complete

    scope :recent, -> { order(created_at: :desc) }

    class << self
      def enqueue_from_verified_webhook!(payment_record:, webhook_event:, reason:)
        validate_enqueue_source!(
          payment_record: payment_record,
          webhook_event: webhook_event,
          reason: reason
        )

        create_or_find_by!(payment_record_id: payment_record.id) do |review_case|
          review_case.payment_webhook_event_id = webhook_event.id
          review_case.store_order_id = payment_record.store_order_id
          review_case.provider = payment_record.provider
          review_case.reason = reason
          review_case.amount_cents = payment_record.amount_cents
          review_case.currency = payment_record.currency
          review_case.status = "open"
        end
      end

      private

      def validate_enqueue_source!(payment_record:, webhook_event:, reason:)
        unless reason.to_s.in?(REASONS)
          raise ArgumentError, "Unsupported late payment reason."
        end
        unless payment_record.provider == "stripe" &&
            payment_record.succeeded? &&
            webhook_event.provider == "stripe" &&
            webhook_event.verified_payload? &&
            webhook_event.event_type.in?(Payments::StripeProvider::PAYMENT_SUCCEEDED_EVENTS)
          raise ArgumentError, "Late payments require a verified Stripe success event."
        end
        return if payment_record.provider == webhook_event.provider

        raise ArgumentError, "Payment provider does not match the webhook provider."
      end
    end

    private

    def associations_match
      return unless payment_record && webhook_event && order

      errors.add(:store_order_id, I18n.t("mcweb.validation_errors.does_not_match_the_payment")) unless payment_record.store_order_id == store_order_id
      errors.add(:provider, I18n.t("mcweb.validation_errors.does_not_match_the_payment")) unless payment_record.provider == provider
      errors.add(:provider, I18n.t("mcweb.validation_errors.does_not_match_the_webhook")) unless webhook_event.provider == provider
      errors.add(:amount_cents, I18n.t("mcweb.validation_errors.does_not_match_the_payment")) unless payment_record.amount_cents == amount_cents
      errors.add(:currency, I18n.t("mcweb.validation_errors.does_not_match_the_payment")) unless payment_record.currency.to_s.casecmp?(currency.to_s)
    end

    def acknowledgement_is_complete
      if acknowledged?
        errors.add(:acknowledged_by, I18n.t("mcweb.validation_errors.is_required")) unless acknowledged_by
        errors.add(:acknowledged_at, I18n.t("mcweb.validation_errors.is_required")) unless acknowledged_at
        errors.add(:disposition, I18n.t("mcweb.validation_errors.is_required")) unless disposition
        errors.add(:review_note, I18n.t("mcweb.validation_errors.is_required")) if review_note.blank?
      elsif acknowledged_by || acknowledged_at || disposition || review_note.present?
        errors.add(:status, I18n.t("mcweb.validation_errors.must_be_acknowledged_before_review_details_are_recorded"))
      end
    end
  end
end
