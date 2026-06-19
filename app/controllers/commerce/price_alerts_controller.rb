# frozen_string_literal: true

module Commerce
  class PriceAlertsController < ApplicationController
    before_action :require_login
    before_action :set_product, only: :create

    def index
      alerts = Commerce::PriceAlert.where(user: current_user).includes(:product, :variant).order(created_at: :desc)

      render inertia: "Commerce/PriceAlerts/Index", props: {
        alerts: alerts.map do |alert|
          product = alert.product
          variant = alert.variant
          current_cents = variant&.price_cents || product.price_cents
          {
            id: alert.id,
            product_name: product.name,
            variant_name: variant&.name,
            product_url: store_product_path(product),
            baseline_price_label: format_money(alert.baseline_price_cents, product.currency),
            current_price_label: format_money(current_cents, product.currency),
            subscribed_at: l(alert.created_at, format: :short),
            unsubscribe_url: store_price_alert_path(alert)
          }
        end
      }
    end

    def create
      variant = @product.variants.find_by(id: params[:variant_id]) if params[:variant_id].present?
      result = Commerce::SubscribePriceAlert.call(user: current_user, product: @product, variant: variant)

      if result.success?
        redirect_back fallback_location: store_wishlist_path, notice: t("mcweb.flash.price_alert_subscribed")
      else
        redirect_back fallback_location: store_wishlist_path, alert: service_error_message(result)
      end
    end

    def destroy
      alert = Commerce::PriceAlert.find_by!(id: params[:id], user: current_user)
      Commerce::UnsubscribePriceAlert.call(user: current_user, product: alert.product)
      redirect_back fallback_location: store_price_alerts_path, notice: t("mcweb.flash.price_alert_unsubscribed")
    end

    private

    def set_product
      @product = Commerce::Product.find_by!(public_id: params[:id])
    end
  end
end
