# frozen_string_literal: true

module Commerce
  class FinanceTaxSnapshot < ApplicationRecord
    belongs_to :order, class_name: "Commerce::Order", foreign_key: :store_order_id

    has_many :finance_documents,
      class_name: "Commerce::FinanceDocument",
      foreign_key: :store_finance_tax_snapshot_id,
      dependent: :restrict_with_error

    validates :tax_rate_bps,
      numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100_000 }
    validates :taxable_base_cents, :tax_cents, :gross_cents,
      numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :currency, :jurisdiction_country, :tax_code, :source_digest, presence: true
    validates :pricing_mode, inclusion: { in: %w[inclusive] }
    validates :rounding_mode, inclusion: { in: %w[half_up] }
    validates :calculation_version, numericality: { only_integer: true, greater_than: 0 }
    validates :order, uniqueness: true
    validate :amounts_conserve

    def readonly?
      persisted?
    end

    private

    def amounts_conserve
      return if taxable_base_cents.to_i + tax_cents.to_i == gross_cents.to_i

      errors.add(:base, I18n.t("mcweb.validation_errors.tax_amounts_must_conserve_the_captured_gross_amount"))
    end
  end
end
