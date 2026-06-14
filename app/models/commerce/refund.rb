module Commerce
  class Refund < ApplicationRecord
    belongs_to :order, class_name: "Commerce::Order", foreign_key: :store_order_id
    belongs_to :payment_record, class_name: "Payments::Record"
    belongs_to :requested_by, class_name: "User", optional: true
    belongs_to :approved_by, class_name: "User", optional: true

    enum :status, { pending: "pending", approved: "approved", rejected: "rejected", completed: "completed" }, validate: true

    validates :amount_cents, numericality: { greater_than: 0 }

    def approve!(by:)
      update!(status: :approved, approved_by: by)
    end

    def complete!
      update!(status: :completed)
      order.refund! if order.may_refund?
    end
  end
end
