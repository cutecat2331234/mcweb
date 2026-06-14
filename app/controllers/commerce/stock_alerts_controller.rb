# frozen_string_literal: true

module Commerce
  class StockAlertsController < ApplicationController
    before_action :require_login

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
  end
end
