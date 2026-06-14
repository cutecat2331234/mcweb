# frozen_string_literal: true

module Commerce
  class CheckoutController < ApplicationController
    before_action :require_login

    def create
      order = Commerce::Order.find_by!(public_id: params[:order_id], user: current_user)
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
        redirect_to commerce_order_path(order), alert: service_error_message(result)
      end
    rescue Payments::Provider::UnknownProviderError => e
      redirect_to commerce_order_path(order), alert: e.message
    rescue ActiveRecord::RecordInvalid => e
      redirect_to commerce_order_path(order), alert: e.record.errors.full_messages.to_sentence
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
