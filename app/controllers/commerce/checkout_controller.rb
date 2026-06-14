# frozen_string_literal: true

module Commerce
  class CheckoutController < ApplicationController
    before_action :require_login

    def show
      cart = Commerce::Cart.find_by(user: current_user)
      items = cart&.items&.includes(:product, :variant) || []
      providers = Payments::ProviderConfig.enabled_providers.map { |config| serialize_checkout_provider(config) }
      currency = items.first&.product&.currency || "CNY"
      subtotal_cents = cart&.subtotal_cents.to_i

      render inertia: "Commerce/Checkout/Show", props: {
        items: items.map { |item|
          {
            product_name: item.product.name,
            variant_name: item.variant&.name,
            quantity: item.quantity,
            total_label: format_money(item.total_cents, item.product.currency)
          }
        },
        subtotalCents: subtotal_cents,
        subtotalLabel: format_money(subtotal_cents, currency),
        providers: providers,
        defaultProvider: providers.first&.dig(:value),
        previewCouponUrl: preview_coupon_store_checkout_path
      }
    end

    def create
      if params[:order_id].blank?
        cart = Commerce::Cart.find_by(user: current_user)
        if cart.nil? || cart.empty?
          return redirect_to store_cart_path, alert: "购物车是空的。"
        end

        order_result = Commerce::CreateOrder.call(
          cart: cart,
          user: current_user,
          coupon_code: checkout_params[:coupon_code],
          notes: checkout_params[:notes]
        )
        unless order_result.success?
          return redirect_to store_checkout_path, alert: service_error_message(order_result)
        end

        order = order_result.value
      else
        order = Commerce::Order.find_by!(public_id: params[:order_id], user: current_user)
      end

      provider_name = checkout_params[:provider].presence || default_provider

      payment_record = order.payment_records.pending.order(created_at: :desc).first
      payment_record ||= Payments::Record.create!(
        order: order,
        provider: provider_name,
        amount_cents: order.total_cents,
        currency: order.currency,
        status: :pending
      )

      result = Payments::Provider.for(provider_name).create_payment(payment_record)

      if result.success?
        redirect_to result.value[:checkout_url], allow_other_host: true
      else
        redirect_to store_order_path(order), alert: service_error_message(result)
      end
    rescue Payments::Provider::UnknownProviderError => e
      redirect_to store_order_path(order), alert: e.message
    rescue ActiveRecord::RecordInvalid => e
      redirect_to store_order_path(order), alert: e.record.errors.full_messages.to_sentence
    end

    def preview_coupon
      cart = Commerce::Cart.find_by(user: current_user)
      subtotal_cents = cart&.subtotal_cents.to_i
      result = Commerce::PreviewCoupon.call(subtotal_cents: subtotal_cents, code: params[:code])

      if result.success?
        render json: {
          code: result.value[:code],
          discount_cents: result.value[:discount_cents],
          total_cents: result.value[:total_cents],
          discount_label: format_money(result.value[:discount_cents], cart&.items&.first&.product&.currency || "CNY"),
          total_label: format_money(result.value[:total_cents], cart&.items&.first&.product&.currency || "CNY")
        }
      else
        render json: { error: service_error_message(result) }, status: :unprocessable_entity
      end
    end

    private

    def checkout_params
      params.fetch(:checkout, {}).permit(:provider, :coupon_code, :notes)
    end

    def default_provider
      Payments::ProviderConfig.enabled_providers.pick(:provider) || "fake"
    end
  end
end
