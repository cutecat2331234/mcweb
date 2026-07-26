module Payments
  class Record < ApplicationRecord
    PROVIDER_MODES = %w[test live].freeze

    belongs_to :order, class_name: "Commerce::Order", foreign_key: :store_order_id
    has_many :attempts, class_name: "Payments::Attempt", foreign_key: :payment_record_id, dependent: :destroy
    has_many :refunds, class_name: "Commerce::Refund", foreign_key: :payment_record_id, dependent: :restrict_with_error
    has_one :late_payment_case,
      class_name: "Payments::LatePaymentCase",
      foreign_key: :payment_record_id,
      dependent: :restrict_with_error

    enum :status, { pending: "pending", processing: "processing", succeeded: "succeeded", failed: "failed", cancelled: "cancelled" }, validate: true

    before_validation :infer_provider_mode_from_metadata

    validates :provider, presence: true
    validates :provider_mode, inclusion: { in: PROVIDER_MODES }, allow_nil: true
    validates :amount_cents, numericality: { greater_than_or_equal_to: 0 }
    validates :currency, presence: true
    validates :provider_payment_id, uniqueness: { scope: :provider }, allow_nil: true
    validate :provider_mode_is_immutable

    def mark_succeeded!(provider_payment_id: nil)
      update!(status: :succeeded, provider_payment_id: provider_payment_id || self.provider_payment_id)
    end

    def mark_failed!
      update!(status: :failed)
    end

    private

    def infer_provider_mode_from_metadata
      return unless provider == "stripe" && provider_mode.blank?

      livemode_values = %w[stripe_livemode stripe_checkout_livemode].filter_map do |key|
        normalize_livemode(metadata.to_h.stringify_keys[key])
      end
      return unless livemode_values.present? && livemode_values.uniq.one?

      self.provider_mode = livemode_values.first
    end

    def normalize_livemode(value)
      case value
      when true, "true" then "live"
      when false, "false" then "test"
      end
    end

    def provider_mode_is_immutable
      return unless will_save_change_to_provider_mode?

      previous_mode = provider_mode_change_to_be_saved&.first
      return if previous_mode.blank?

      errors.add(:provider_mode, "cannot be changed after it is assigned")
    end
  end
end
