# frozen_string_literal: true

module Commerce
  class WishlistController < ApplicationController
    before_action :require_login

    def index
      items = Commerce::WishlistItem
        .where(user: current_user)
        .includes(product: :category)
        .order(created_at: :desc)

      render inertia: "Commerce/Wishlist/Index", props: {
        products: items.map { |item| serialize_product_list_item(item.product) }
      }
    end

    def toggle
      product = Commerce::Product.available.find_by!(public_id: params[:id])
      result = Commerce::ToggleWishlist.call(user: current_user, product: product)

      if result.success?
        redirect_back fallback_location: store_product_path(product),
                      notice: result.value[:wishlisted] ? "已加入心愿单。" : "已从心愿单移除。"
      else
        redirect_back fallback_location: store_product_path(product), alert: service_error_message(result)
      end
    end
  end
end
