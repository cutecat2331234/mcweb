# frozen_string_literal: true

module Commerce
  class RefundsController < ApplicationController
    before_action :require_login

    def destroy
      order = Commerce::Order.where(user: current_user).find_by!(public_id: params[:id])
      refund = order.refunds.find(params[:refund_id])
      result = Commerce::WithdrawRefund.call(order: order, refund: refund, user: current_user)

      if result.success?
        redirect_to store_order_path(order), notice: t("mcweb.flash.refund_withdrawn")
      else
        redirect_to store_order_path(order), alert: service_error_message(result)
      end
    end
  end
end
