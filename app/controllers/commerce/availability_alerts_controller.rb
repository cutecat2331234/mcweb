# frozen_string_literal: true

module Commerce
  class AvailabilityAlertsController < ApplicationController
    before_action :require_login

    def index
      alerts = Commerce::ProductAvailabilityAlert
        .where(user: current_user)
        .includes(:product)
        .order(created_at: :desc)

      render inertia: "Commerce/AvailabilityAlerts/Index", props: {
        alerts: alerts.filter_map do |alert|
          product = alert.product
          next unless product && Commerce::StoreFeatures.product_visible?(product)

          {
            id: alert.id,
            product_name: product.name,
            product_url: alert.product.coming_soon? ? preview_store_product_path(alert.product) : store_product_path(alert.product),
            available: product.available? && !product.coming_soon?,
            subscribed_at: l(alert.created_at, format: :short),
            unsubscribe_url: store_availability_alert_path(alert)
          }
        end
      }
    end

    def create
      product = Commerce::Product.upcoming.find_by!(public_id: params[:product_id])
      raise ActiveRecord::RecordNotFound unless Commerce::StoreFeatures.product_visible?(product)

      result = Commerce::SubscribeProductAvailabilityAlert.call(user: current_user, product: product)

      if result.success?
        redirect_back fallback_location: store_products_path, notice: t("mcweb.flash.availability_subscribed")
      else
        redirect_back fallback_location: store_products_path, alert: service_error_message(result)
      end
    end

    def destroy
      alert = Commerce::ProductAvailabilityAlert.find_by!(id: params[:id], user: current_user)
      Commerce::UnsubscribeProductAvailabilityAlert.call(user: current_user, product: alert.product)
      redirect_back fallback_location: store_availability_alerts_path, notice: t("mcweb.flash.availability_unsubscribed")
    end
  end
end
