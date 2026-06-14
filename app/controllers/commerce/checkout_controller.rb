# frozen_string_literal: true

module Commerce
  class CheckoutController < ApplicationController
    before_action :require_login

    def show
      @cart = Commerce::Cart.find_by(user: current_user)
      @cart_items = @cart&.items&.includes(:product, :variant) || []
    end

    def create
      if params[:order_id].blank?
        cart = Commerce::Cart.find_by(user: current_user)
        if cart.nil? || cart.empty?
          return redirect_to store_cart_path, alert: "Your cart is empty."
        end

        order_result = Commerce::CreateOrder.call(cart: cart, user: current_user)
        unless order_result.success?
          return redirect_to store_checkout_path, alert: service_error_message(order_result)
        end

        order = order_result.value
      else
        order = Commerce::Order.find_by!(public_id: params[:order_id], user: current_user)
      end

      provider_name = checkout_params[:provider].presence || default_provider

      payment_record = Payments::Record.create!(
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

    private

    def checkout_params
      params.fetch(:checkout, {}).permit(:provider)
    end

    def default_provider
      Payments::ProviderConfig.enabled_providers.pick(:provider) || "fake"
    end
  end
end
