# frozen_string_literal: true

module Commerce
  class CartsController < ApplicationController
    before_action :set_cart

    def show
      @cart_items = @cart.items.includes(:product, :variant)
    end

    def update
      if params[:product_id].present?
        product = Commerce::Product.available.find(params[:product_id])
        variant = product.variants.find_by(id: params[:variant_id])
        quantity = params[:quantity].to_i
        quantity = 1 if quantity < 1

        @cart.add_item!(product: product, variant: variant, quantity: quantity)
      elsif params[:item_id].present?
        item = @cart.items.find(params[:item_id])
        if params[:quantity].to_i.positive?
          item.update!(quantity: params[:quantity].to_i)
        else
          item.destroy!
        end
      end

      redirect_to store_cart_path, notice: "Cart updated."
    rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid => e
      redirect_to store_cart_path, alert: e.message
    end

    private

    def set_cart
      @cart = find_user_cart || find_session_cart || create_session_cart
      persist_cart_cookie(@cart) unless logged_in?
    end

    def find_user_cart
      return unless logged_in?

      Commerce::Cart.find_or_create_by!(user: current_user)
    end

    def find_session_cart
      token = cookies.signed[:cart_token]
      Commerce::Cart.find_by(session_token: token) if token.present?
    end

    def create_session_cart
      Commerce::Cart.create!
    end

    def persist_cart_cookie(cart)
      cookies.signed[:cart_token] = {
        value: cart.session_token,
        httponly: true,
        same_site: :lax,
        expires: 30.days
      }
    end
  end
end
