# frozen_string_literal: true

module Commerce
  class BeginOrderPayment < ApplicationService
    def initialize(order:)
      @order = order
    end

    def call
      Commerce::Order.transaction do
        order = Commerce::Order.lock.find(@order.id)
        order.reload

        unless order.payable?
          return ServiceResult.failure(
            error: order.payment_expired? ? "order_payment_expired" : "order_cannot_continue_payment"
          )
        end

        if order.pending? && order.may_submit_payment?
          order.submit_payment!
        elsif !order.awaiting_payment?
          return ServiceResult.failure(error: "order_cannot_continue_payment")
        end
      end

      ServiceResult.success(@order.reload)
    rescue AASM::InvalidTransition
      ServiceResult.failure(error: "order_cannot_continue_payment")
    end
  end
end
