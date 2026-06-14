module Payments
  class Record < ApplicationRecord
    belongs_to :order, class_name: "Commerce::Order", foreign_key: :store_order_id
    has_many :attempts, class_name: "Payments::Attempt", foreign_key: :payment_record_id, dependent: :destroy
    has_many :refunds, class_name: "Commerce::Refund", foreign_key: :payment_record_id, dependent: :restrict_with_error

    enum :status, { pending: "pending", processing: "processing", succeeded: "succeeded", failed: "failed", cancelled: "cancelled" }, validate: true

    validates :provider, presence: true
    validates :amount_cents, numericality: { greater_than: 0 }
    validates :currency, presence: true
    validates :provider_payment_id, uniqueness: { scope: :provider }, allow_nil: true

    def mark_succeeded!(provider_payment_id: nil)
      update!(status: :succeeded, provider_payment_id: provider_payment_id || self.provider_payment_id)
    end

    def mark_failed!
      update!(status: :failed)
    end
  end
end
