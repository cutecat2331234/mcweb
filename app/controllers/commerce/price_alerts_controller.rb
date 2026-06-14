# frozen_string_literal: true

module Commerce
  class PriceAlertsController < ApplicationController
    before_action :require_login
    before_action :set_product

    def create
      variant = @product.variants.find_by(id: params[:variant_id]) if params[:variant_id].present?
      result = Commerce::SubscribePriceAlert.call(user: current_user, product: @product, variant: variant)

      if result.success?
        redirect_back fallback_location: store_wishlist_path, notice: "已订阅降价提醒。"
      else
        redirect_back fallback_location: store_wishlist_path, alert: service_error_message(result)
      end
    end

    private

    def set_product
      @product = Commerce::Product.find_by!(public_id: params[:id])
    end
  end
end
