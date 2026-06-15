# frozen_string_literal: true

module Commerce
  class WishlistController < ApplicationController
    before_action :require_login, except: %i[public_show]

    def index
      items = Commerce::WishlistItem
        .where(user: current_user)
        .includes(product: %i[category variants], variant: [])
        .order(created_at: :desc)

      share = Commerce::EnsureWishlistShareToken.call(user: current_user)

      render inertia: "Commerce/Wishlist/Index", props: {
        products: items.map do |item|
          product = item.product
          variant = item.variant
          data = serialize_product_list_item(product)
          if product.coming_soon?
            data[:url] = preview_store_product_path(product)
            data[:coming_soon] = true
            data[:available_at_label] = product.available_at ? l(product.available_at, format: :short) : nil
            data[:in_stock] = false
          end
          if variant
            data[:price_label] = format_money(variant.price_cents, product.currency)
            data[:in_stock] = variant.in_stock?
            data[:low_stock] = variant.low_stock?
          end
          alert = Commerce::PriceAlert.find_by(user: current_user, product: product)
          data.merge(
            wishlist_url: wishlist_store_product_path(product),
            update_note_url: store_note_wishlist_path(product.public_id),
            note: item.note.to_s,
            add_to_cart_url: store_add_wishlist_item_to_cart_path(product.public_id),
            saved_variant_id: variant&.id,
            saved_variant_name: variant&.name,
            price_alert_url: price_alert_store_product_path(product),
            has_price_alert: alert.present?
          )
        end,
        shareUrl: share.success? ? store_public_wishlist_url(share.value[:token]) : nil,
        addAllToCartUrl: store_add_all_to_cart_wishlist_path
      }
    end

    def share
      result = Commerce::EnsureWishlistShareToken.call(user: current_user)
      if result.success?
        redirect_to store_wishlist_path, notice: "分享链接已生成。"
      else
        redirect_to store_wishlist_path, alert: service_error_message(result)
      end
    end

    def public_show
      user = User.find_by!(wishlist_share_token: params[:token])
      items = Commerce::WishlistItem.where(user: user).includes(:product, :variant).order(created_at: :desc)

      render inertia: "Commerce/Wishlist/Public", props: {
        owner: user.display_name || user.username,
        products: items.map do |item|
          data = serialize_product_list_item(item.product)
          data.merge(saved_variant_name: item.variant&.name, note: item.note.to_s)
        end
      }
    end

    def toggle
      product = Commerce::Product.active.find_by!(public_id: params[:id])
      unless product.available? || product.coming_soon?
        return redirect_back fallback_location: store_products_path, alert: "商品不可加入心愿单。"
      end

      variant = product.variants.find_by(id: params[:variant_id]) if params[:variant_id].present?
      result = Commerce::ToggleWishlist.call(user: current_user, product: product, variant: variant)

      if result.success?
        notice = result.value[:wishlisted] ? "已加入心愿单。" : "已从心愿单移除。"
        redirect_back fallback_location: store_product_path(product), notice: notice
      else
        redirect_back fallback_location: store_product_path(product), alert: service_error_message(result)
      end
    end

    def add_to_cart
      product = Commerce::Product.available.find_by!(public_id: params[:product_id])
      result = Commerce::AddWishlistItemToCart.call(user: current_user, product: product)

      if result.success?
        redirect_to store_cart_path, notice: "已加入购物车。"
      else
        redirect_to store_wishlist_path, alert: service_error_message(result)
      end
    end

    def add_all_to_cart
      result = Commerce::AddWishlistToCart.call(user: current_user)

      if result.success?
        notice = "已将 #{result.value[:added]} 件商品加入购物车。"
        notice += " 跳过：#{result.value[:skipped].join('、')}" if result.value[:skipped].any?
        redirect_to store_cart_path, notice: notice
      else
        redirect_to store_wishlist_path, alert: service_error_message(result)
      end
    end

    def update_note
      product = Commerce::Product.available.find_by!(public_id: params[:product_id])
      result = Commerce::UpdateWishlistNote.call(user: current_user, product: product, note: params[:note])

      if result.success?
        redirect_to store_wishlist_path, notice: "备注已保存。"
      else
        redirect_to store_wishlist_path, alert: service_error_message(result)
      end
    end
  end
end
