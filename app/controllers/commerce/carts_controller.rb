# frozen_string_literal: true

module Commerce
  class CartsController < ApplicationController
    before_action :set_cart

    def show
      items = @cart.items.includes(:product, :variant)

      render inertia: "Commerce/Carts/Show", props: {
        items: items.map { |item| serialize_cart_item(item) },
        subtotalLabel: format_money(@cart.subtotal_cents, items.first&.product&.currency || "CNY"),
        subtotalCents: @cart.subtotal_cents,
        loggedIn: logged_in?,
        previewCouponUrl: preview_coupon_store_cart_path
      }
    end

    def preview_coupon
      subtotal_cents = @cart.subtotal_cents
      result = Commerce::PreviewCoupon.call(subtotal_cents: subtotal_cents, code: params[:code])

      if result.success?
        render json: {
          code: result.value[:code],
          discount_cents: result.value[:discount_cents],
          total_cents: result.value[:total_cents],
          discount_label: format_money(result.value[:discount_cents], @cart.items.first&.product&.currency || "CNY"),
          total_label: format_money(result.value[:total_cents], @cart.items.first&.product&.currency || "CNY")
        }
      else
        render json: { error: service_error_message(result) }, status: :unprocessable_entity
      end
    end

    def update
      if params[:product_id].present?
        product = Commerce::Product.available.find(params[:product_id])
        variant = product.variants.find_by(id: params[:variant_id])
        quantity = params[:quantity].to_i
        quantity = 1 if quantity < 1

        validation = Commerce::ValidateCartItem.call(
          user: current_user,
          product: product,
          variant: variant,
          quantity: quantity,
          cart: @cart
        )
        unless validation.success?
          return redirect_to request.referer.presence || store_cart_path, alert: service_error_message(validation)
        end

        @cart.add_item!(product: product, variant: variant, quantity: quantity)
      elsif params[:item_id].present?
        item = @cart.items.find(params[:item_id])
        if params[:quantity].to_i.positive?
          validation = Commerce::ValidateCartItem.call(
            user: current_user,
            product: item.product,
            variant: item.variant,
            quantity: params[:quantity].to_i,
            cart: @cart,
            replace_quantity: true
          )
          unless validation.success?
            return redirect_to store_cart_path, alert: service_error_message(validation)
          end

          item.update!(quantity: params[:quantity].to_i)
        else
          item.destroy!
        end
      end

      redirect_to store_cart_path, notice: "购物车已更新。"
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
