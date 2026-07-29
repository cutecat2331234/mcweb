# frozen_string_literal: true

module Payments
  class ReconciliationDiscrepancy < ApplicationRecord
    include HasPublicId

    READ_PERMISSION = "store.payments.reconciliation.read"
    REVIEW_PERMISSION = "store.payments.reconciliation.review"
    SUBJECT_TYPES = %w[payment refund].freeze
    STATUSES = %w[open acknowledged ignored resolved].freeze
    KINDS = %w[
      provider_payment_missing_local
      local_payment_missing_provider
      payment_reference_missing
      payment_amount_mismatch
      payment_currency_mismatch
      payment_status_mismatch
      payment_metadata_mismatch
      payment_environment_unknown
      order_amount_mismatch
      order_currency_mismatch
      order_status_mismatch
      provider_refund_missing_local
      local_refund_missing_provider
      refund_reference_missing
      refund_amount_mismatch
      refund_currency_mismatch
      refund_status_mismatch
      refund_metadata_mismatch
      refund_environment_unknown
      refund_payment_mismatch
    ].freeze

    belongs_to :run,
      class_name: "Payments::ReconciliationRun",
      inverse_of: :discrepancies
    belongs_to :payment_record, class_name: "Payments::Record", optional: true
    belongs_to :refund, class_name: "Commerce::Refund", optional: true
    belongs_to :order,
      class_name: "Commerce::Order",
      foreign_key: :store_order_id,
      optional: true
    belongs_to :reviewed_by, class_name: "User", optional: true

    enum :status, STATUSES.index_with(&:itself), validate: true

    attr_readonly :run_id,
      :provider,
      :mode,
      :subject_type,
      :kind,
      :reference_masked,
      :reference_digest,
      :fingerprint,
      :payment_record_id,
      :refund_id,
      :store_order_id,
      :local_status,
      :provider_status,
      :local_amount_cents,
      :provider_amount_cents,
      :local_currency,
      :provider_currency,
      :first_seen_at

    validates :provider, :mode, :first_seen_at, :last_seen_at, presence: true
    validates :mode, inclusion: { in: Payments::ReconciliationRun::MODES }
    validates :subject_type, inclusion: { in: SUBJECT_TYPES }
    validates :kind, inclusion: { in: KINDS }
    validates :reference_digest, :fingerprint, format: { with: /\A\h{64}\z/ }
    validates :fingerprint, uniqueness: true
    validates :local_amount_cents,
      :provider_amount_cents,
      numericality: { only_integer: true, greater_than_or_equal_to: 0 },
      allow_nil: true
    validate :review_is_complete
    validate :associations_match

    scope :recent, -> { order(created_at: :desc) }

    private

    def review_is_complete
      if open?
        if reviewed_by || reviewed_at || resolved_at || review_note.present?
          errors.add(:status, I18n.t("mcweb.validation_errors.must_be_reviewed_before_review_details_are_recorded"))
        end
      elsif resolved?
        errors.add(:resolved_at, I18n.t("mcweb.validation_errors.is_required")) unless resolved_at
        if reviewed_by || reviewed_at || review_note.present?
          errors.add(:status, I18n.t("mcweb.validation_errors.cannot_resolve_a_manually_reviewed_discrepancy"))
        end
      else
        errors.add(:reviewed_by, I18n.t("mcweb.validation_errors.is_required")) unless reviewed_by
        errors.add(:reviewed_at, I18n.t("mcweb.validation_errors.is_required")) unless reviewed_at
        errors.add(:review_note, I18n.t("mcweb.validation_errors.is_required")) if review_note.blank?
        errors.add(:resolved_at, I18n.t("mcweb.validation_errors.cannot_be_set_on_a_reviewed_discrepancy")) if resolved_at
      end
    end

    def associations_match
      if subject_type == "payment" && refund_id.present?
        errors.add(:refund, I18n.t("mcweb.validation_errors.cannot_be_attached_to_a_payment_discrepancy"))
      elsif subject_type == "refund" && payment_record_id.present? && refund.nil?
        errors.add(:payment_record, I18n.t("mcweb.validation_errors.must_be_attached_through_a_local_refund"))
      end

      if payment_record && order && payment_record.store_order_id != store_order_id
        errors.add(:store_order_id, I18n.t("mcweb.validation_errors.does_not_match_the_payment"))
      end
      if refund && order && refund.store_order_id != store_order_id
        errors.add(:store_order_id, I18n.t("mcweb.validation_errors.does_not_match_the_refund"))
      end
      if refund && payment_record && refund.payment_record_id != payment_record_id
        errors.add(:payment_record_id, I18n.t("mcweb.validation_errors.does_not_match_the_refund"))
      end
    end
  end
end
