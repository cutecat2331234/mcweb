# frozen_string_literal: true

module Commerce
  class OrderDisputesController < ApplicationController
    include PrivateNoStoreResponse

    before_action :require_login
    before_action :set_owned_order
    before_action :set_owned_dispute, only: :destroy

    def create
      result = Commerce::Disputes::CreateCustomerDispute.call(
        order: @order,
        actor: current_user,
        request_id: dispute_params[:request_id],
        reason_kind: dispute_params[:reason_kind],
        description: dispute_params[:description],
        amount_cents: dispute_params[:amount_cents],
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      if result.success?
        redirect_to store_order_path(@order),
                    notice: t("mcweb.flash.customer_dispute_opened")
      else
        redirect_to store_order_path(@order), alert: service_error_message(result)
      end
    end

    def destroy
      result = Commerce::Disputes::WithdrawCustomerDispute.call(
        order: @order,
        dispute: @dispute,
        actor: current_user,
        request_id: dispute_params[:request_id],
        reason: dispute_params[:withdraw_reason],
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      if result.success?
        redirect_to store_order_path(@order),
                    notice: t("mcweb.flash.customer_dispute_withdrawn")
      else
        redirect_to store_order_path(@order), alert: service_error_message(result)
      end
    end

    private

    def set_owned_order
      @order = Commerce::Order.where(user: current_user)
        .find_by!(public_id: params[:order_id])
    end

    def set_owned_dispute
      @dispute = @order.disputes.find_by!(public_id: params[:public_id])
    end

    def dispute_params
      params.require(:dispute).permit(
        :request_id,
        :reason_kind,
        :description,
        :amount_cents,
        :withdraw_reason
      )
    end
  end
end
