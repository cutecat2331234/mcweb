# frozen_string_literal: true

module Commerce
  class StockAlertsController < ApplicationController
    before_action :require_login

    def index
      alerts = Commerce::StockAlert.where(user: current_user).includes(:product, :variant).order(created_at: :desc)

      render inertia: "Commerce/StockAlerts/Index", props: {
        alerts: alerts.map do |alert|
          product = alert.product
          {
            id: alert.id,
            product_name: product.name,
            variant_name: alert.variant&.name,
            product_url: store_product_path(product),
            unsubscribe_url: store_stock_alert_path(alert)
          }
        end
      }
    end

    def create
      product = Commerce::Product.available.find_by!(public_id: params[:product_id])
      variant = product.variants.find_by(id: params[:variant_id])

      result = Commerce::SubscribeStockAlert.call(user: current_user, product: product, variant: variant)

      if result.success?
        redirect_to store_product_path(product), notice: "到货通知已订阅。"
      else
        redirect_to store_product_path(product), alert: service_error_message(result)
      end
    end

    def destroy
      alert = Commerce::StockAlert.find_by!(id: params[:id], user: current_user)
      product = alert.product
      Commerce::UnsubscribeStockAlert.call(user: current_user, product: product, variant: alert.variant)
      redirect_back fallback_location: store_stock_alerts_path, notice: "已取消到货通知。"
    end
  end
end
