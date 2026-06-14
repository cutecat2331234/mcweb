# frozen_string_literal: true

module Commerce
  class OrdersController < ApplicationController
    before_action :require_login
    before_action :set_order, only: %i[show cancel]

    def index
      orders = Commerce::Order.where(user: current_user).includes(:items).recent

      render inertia: "Commerce/Orders/Index", props: {
        orders: orders.map { |order| serialize_order_list_item(order) }
      }
    end

    def show
      render inertia: "Commerce/Orders/Show", props: {
        order: serialize_order_detail(@order)
      }
    end

    def cancel
      unless @order.pending? || @order.awaiting_payment?
        return redirect_to store_order_path(@order), alert: "此订单无法取消。"
      end

      @order.cancel! if @order.may_cancel?
      redirect_to store_order_path(@order), notice: "订单已取消。"
    rescue AASM::InvalidTransition
      redirect_to store_order_path(@order), alert: "无法取消此订单。"
    end

    def new
      cart = Commerce::Cart.find_by(user: current_user)
      redirect_to store_cart_path, alert: "Your cart is empty." if cart.nil? || cart.empty?
    end

    def create
      cart = Commerce::Cart.find_by(user: current_user)
      return redirect_to store_cart_path, alert: "Your cart is empty." if cart.nil? || cart.empty?

      result = Commerce::CreateOrder.call(
        cart: cart,
        user: current_user,
        notes: order_params[:notes]
      )

      if result.success?
        redirect_to store_order_path(result.value), notice: "Order created."
      else
        redirect_to new_store_order_path, alert: service_error_message(result)
      end
    end

    private

    def set_order
      @order = Commerce::Order.where(user: current_user).includes(:items, :fulfillments).find_by!(public_id: params[:id])
    end

    def order_params
      params.fetch(:order, {}).permit(:notes)
    end
  end
end
