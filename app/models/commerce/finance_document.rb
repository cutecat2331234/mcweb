# frozen_string_literal: true

module Commerce
  class FinanceDocument < ApplicationRecord
    include HasPublicId

    self.table_name = "store_finance_documents"

    belongs_to :order, class_name: "Commerce::Order", foreign_key: :store_order_id
    belongs_to :refund,
      class_name: "Commerce::Refund",
      foreign_key: :store_refund_id,
      optional: true
    belongs_to :tax_snapshot,
      class_name: "Commerce::FinanceTaxSnapshot",
      foreign_key: :store_finance_tax_snapshot_id
    belongs_to :supersedes,
      class_name: "Commerce::FinanceDocument",
      optional: true
    has_one :superseded_by,
      class_name: "Commerce::FinanceDocument",
      foreign_key: :supersedes_id,
      dependent: :restrict_with_error,
      inverse_of: :supersedes
    has_many :events,
      class_name: "Commerce::FinanceDocumentEvent",
      foreign_key: :store_finance_document_id,
      dependent: :restrict_with_error

    enum :document_kind, {
      invoice: "invoice",
      refund_receipt: "refund_receipt"
    }, validate: true

    enum :status, {
      issued: "issued",
      superseded: "superseded",
      voided: "voided"
    }, validate: true

    validates :document_number, :channel, :currency, :source_digest, presence: true
    validates :version, numericality: { only_integer: true, greater_than: 0 }
    validates :net_amount_cents, :tax_amount_cents, :gross_amount_cents,
      numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :document_number, uniqueness: { scope: :version }
    validate :amounts_conserve
    validate :source_matches_kind
    validate :issued_content_is_immutable, on: :update
    validate :state_transition_is_allowed, on: :update

    before_destroy { throw(:abort) }

    scope :current, -> { issued }
    scope :recent_first, -> { order(issued_at: :desc, id: :desc) }

    def editable_transition_attributes
      %w[status superseded_at voided_at]
    end

    private

    def amounts_conserve
      return if net_amount_cents.to_i + tax_amount_cents.to_i == gross_amount_cents.to_i

      errors.add(:base, I18n.t("mcweb.validation_errors.document_amounts_must_conserve_the_gross_amount"))
    end

    def source_matches_kind
      if invoice? && store_refund_id.present?
        errors.add(:refund, I18n.t("mcweb.validation_errors.must_be_absent_for_an_invoice"))
      elsif refund_receipt? && store_refund_id.blank?
        errors.add(:refund, I18n.t("mcweb.validation_errors.must_be_present_for_a_refund_receipt"))
      end
    end

    def issued_content_is_immutable
      changed = changes_to_save.keys - editable_transition_attributes
      return if changed.empty?

      errors.add(:base, I18n.t("mcweb.validation_errors.issued_finance_document_content_is_immutable"))
    end

    def state_transition_is_allowed
      return unless will_save_change_to_status?

      from, to = status_change_to_be_saved
      return if from == "issued" && %w[superseded voided].include?(to)

      errors.add(:status, I18n.t("mcweb.validation_errors.transition_is_not_allowed"))
    end
  end
end
