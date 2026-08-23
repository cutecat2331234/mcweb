# frozen_string_literal: true

module Commerce
  module FinancialLocking
    class BindingMismatch < StandardError; end

    module_function

    def lock_order_payment!(order_id:, payment_record_id:)
      order = Commerce::Order.lock.find(order_id)
      payment = Payments::Record.lock.find(payment_record_id)
      raise BindingMismatch unless payment.store_order_id == order.id

      [ order, payment ]
    end

    def lock_order_payment_refund!(order_id:, payment_record_id:, refund_id:)
      order, payment = lock_order_payment!(order_id:, payment_record_id:)
      refund = Commerce::Refund.lock.find(refund_id)
      unless refund.store_order_id == order.id && refund.payment_record_id == payment.id
        raise BindingMismatch
      end

      [ order, payment, refund ]
    end

    def lock_order_payment_dispute!(order_id:, payment_record_id:, dispute_id:)
      order, payment = lock_order_payment!(order_id:, payment_record_id:)
      dispute = Commerce::Dispute.lock.find(dispute_id)
      unless dispute.store_order_id == order.id && dispute.payment_record_id == payment.id
        raise BindingMismatch
      end

      [ order, payment, dispute ]
    end

    def lock_order_payment_disputes!(order_id:, payment_record_id:)
      order, payment = lock_order_payment!(order_id:, payment_record_id:)
      disputes = payment.disputes.order(:created_at, :id).lock.to_a
      if disputes.any? { |dispute| dispute.store_order_id != order.id }
        raise BindingMismatch
      end

      [ order, payment, disputes ]
    end

    def lock_order_payment_refunds_disputes!(order_id:, payment_record_id:)
      order, payment = lock_order_payment!(order_id:, payment_record_id:)
      refunds = payment.refunds.order(:created_at, :id).lock.to_a
      disputes = payment.disputes.order(:created_at, :id).lock.to_a
      if refunds.any? { |refund| refund.store_order_id != order.id } ||
          disputes.any? { |dispute| dispute.store_order_id != order.id }
        raise BindingMismatch
      end

      [ order, payment, refunds, disputes ]
    end
  end
end
