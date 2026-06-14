# frozen_string_literal: true

module Commerce
  class OrderMailer < ApplicationMailer
    def order_created(order_id)
      @order = Commerce::Order.find(order_id)
      mail(to: @order.user.email, subject: "订单确认 #{@order.order_number}")
    end

    def payment_confirmed(order_id)
      @order = Commerce::Order.find(order_id)
      mail(to: @order.user.email, subject: "支付成功 #{@order.order_number}")
    end

    def order_cancelled(order_id)
      @order = Commerce::Order.find(order_id)
      mail(to: @order.user.email, subject: "订单已取消 #{@order.order_number}")
    end

    def refund_processed(refund_id)
      @refund = Commerce::Refund.find(refund_id)
      @order = @refund.order
      mail(to: @order.user.email, subject: "退款处理通知 #{@order.order_number}")
    end

    def order_fulfilled(order_id)
      @order = Commerce::Order.find(order_id)
      mail(to: @order.user.email, subject: "商品已发货 #{@order.order_number}")
    end
  end
end
