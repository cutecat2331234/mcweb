# frozen_string_literal: true

module Commerce
  class OrdersController < ApplicationController
    before_action :require_login
    before_action :set_order, only: %i[show]

    def index
      @orders = Commerce::Order.where(user: current_user).includes(:items).recent
    end

    def show
    end

    def new
      @cart = Commerce::Cart.find_by(user: current_user)
      redirect_to commerce_cart_path, alert: "Your cart is empty." if @cart.nil? || @cart.empty?
    end

    def create
      cart = Commerce::Cart.find_by(user: current_user)
      return redirect_to commerce_cart_path, alert: "Your cart is empty." if cart.nil? || cart.empty?

      result = Commerce::CreateOrder.call(
        cart: cart,
        user: current_user,
        notes: order_params[:notes]
      )

      if result.success?
        redirect_to commerce_order_path(result.value), notice: "Order created."
      else
        redirect_to new_commerce_order_path, alert: service_error_message(result)
      end
    end

    private

    def set_order
      @order = Commerce::Order.where(user: current_user).find_by!(public_id: params[:id])
    end

    def order_params
      params.fetch(:order, {}).permit(:notes)
    end
  end
end
