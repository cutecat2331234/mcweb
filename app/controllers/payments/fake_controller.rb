# frozen_string_literal: true

module Payments
  class FakeController < ApplicationController
    before_action :require_login
    before_action :set_payment

    def show
      order = @payment.order
      return redirect_to root_path, alert: t("mcweb.flash.payment_access_denied") unless order.user_id == current_user.id
      unless order.payable?
        message = order.payment_expired? ? "订单支付已过期。" : "该订单无法继续支付。"
        return redirect_to store_order_path(order), alert: message
      end

      if @payment.status == "pending" && @payment.amount_cents != order.total_cents
        @payment.update!(status: "failed")
        return redirect_to store_order_path(order), alert: t("mcweb.flash.payment_expired")
      end

      render inertia: "Payments/Fake/Show", props: {
        paymentId: @payment.provider_payment_id,
        amountLabel: format_money(@payment.amount_cents, @payment.currency),
        order: {
          id: order.public_id,
          order_number: order.order_number,
          url: store_order_path(order)
        },
        payUrl: fake_payment_path(@payment.provider_payment_id)
      }
    end

    def create
      order = @payment.order
      return redirect_to root_path, alert: t("mcweb.flash.payment_access_denied") unless order.user_id == current_user.id
      unless order.payable?
        message = order.payment_expired? ? "订单支付已过期。" : "该订单无法继续支付。"
        return redirect_to store_order_path(order), alert: message
      end

      if @payment.status == "pending" && @payment.amount_cents != order.total_cents
        @payment.update!(status: "failed")
        return redirect_to store_order_path(order), alert: t("mcweb.flash.payment_expired")
      end

      result = Commerce::ConfirmPayment.call(
        payment_record: @payment,
        provider_payment_id: @payment.provider_payment_id
      )

      if result.success?
        redirect_to store_order_path(order), notice: t("mcweb.flash.payment_success")
      else
        redirect_to fake_payment_path(@payment.provider_payment_id), alert: service_error_message(result)
      end
    end

    private

    def set_payment
      @payment = Payments::Record.find_by!(provider: "fake", provider_payment_id: params[:id])
    end
  end
end
