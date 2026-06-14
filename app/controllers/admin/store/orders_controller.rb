# frozen_string_literal: true

module Admin
  module Store
    class OrdersController < BaseController
      before_action -> { require_permission("admin.store.manage") }
      before_action :set_order, only: %i[show update]

      def index
        @orders = ::Commerce::Order.recent.limit(50)
      end

      def show
        @fulfillments = @order.fulfillments.includes(:order_item)
      end

      def update
        if @order.update(order_params)
          redirect_to admin_store_order_path(@order), notice: "Order updated."
        else
          redirect_to admin_store_order_path(@order), alert: @order.errors.full_messages.to_sentence
        end
      end

      private

      def set_order
        @order = ::Commerce::Order.find_by!(public_id: params[:id])
      end

      def order_params
        params.expect(order: %i[status notes])[:order]
      end
    end
  end
end
