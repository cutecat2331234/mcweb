# frozen_string_literal: true

module Commerce
  class StockAlertsController < ApplicationController
    before_action :require_login

    def index
      alerts = Commerce::StockAlert.where(user: current_user).includes(:product, :variant).order(created_at: :desc)

      render inertia: "Commerce/StockAlerts/Index", props: {
        alerts: alerts.map do |alert|
          product = alert.product
          in_stock = alert.variant ? alert.variant.in_stock? : product.in_stock?
          {
            id: alert.id,
            product_name: product.name,
            variant_name: alert.variant&.name,
            product_url: store_product_path(product),
            in_stock: in_stock,
            subscribed_at: l(alert.created_at, format: :short),
            unsubscribe_url: store_stock_alert_path(alert),
            add_to_cart_url: in_stock ? add_to_cart_store_stock_alert_path(alert) : nil
          }
        end
      }
    end

    def create
      product = Commerce::Product.available.find_by!(public_id: params[:product_id])
      variant = product.variants.find_by(id: params[:variant_id])

      result = Commerce::SubscribeStockAlert.call(user: current_user, product: product, variant: variant)

      if result.success?
        redirect_to store_product_path(product), notice: t("mcweb.flash.stock_alert_subscribed")
      else
        redirect_to store_product_path(product), alert: service_error_message(result)
      end
    end

    def add_to_cart
      alert = Commerce::StockAlert.find_by!(id: params[:id], user: current_user)
      product = alert.product
      variant = alert.variant
      in_stock = variant ? variant.in_stock? : product.in_stock?
      return redirect_to store_stock_alerts_path, alert: t("mcweb.flash.stock_alert_no_stock") unless in_stock

      cart = Commerce::Cart.find_or_create_by!(user: current_user)
      validation = Commerce::ValidateCartItem.call(
        user: current_user,
        product: product,
        variant: variant,
        quantity: 1,
        cart: cart
      )
      return redirect_to store_stock_alerts_path, alert: service_error_message(validation) unless validation.success?

      cart.add_item!(product: product, variant: variant, quantity: 1)
      redirect_to store_cart_path, notice: t("mcweb.flash.added_to_cart")
    end

    def destroy
      alert = Commerce::StockAlert.find_by!(id: params[:id], user: current_user)
      product = alert.product
      Commerce::UnsubscribeStockAlert.call(user: current_user, product: product, variant: alert.variant)
      redirect_back fallback_location: store_stock_alerts_path, notice: t("mcweb.flash.stock_alert_unsubscribed")
    end
  end
end
