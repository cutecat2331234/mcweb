# frozen_string_literal: true

module Commerce
  class WishlistController < ApplicationController
    include Commerce::WishlistCompareImportable

    before_action :require_login, except: %i[public_show]

    def index
      all_items = Commerce::WishlistItem
        .where(user: current_user)
        .includes(product: %i[category variants], variant: [])
        .order(created_at: :desc)
        .to_a

      total_count = all_items.size
      items = sort_wishlist_items(filter_wishlist_items(all_items))

      share = Commerce::EnsureWishlistShareToken.call(user: current_user)
      availability_alerts = Commerce::ProductAvailabilityAlert
        .where(user: current_user, store_product_id: all_items.map(&:store_product_id))
        .index_by(&:store_product_id)

      compared_ids = Array(session[:compare_product_ids])

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
            alert = availability_alerts[product.id]
            data[:availability_alert_url] = availability_alert_store_product_path(product)
            data[:has_availability_alert] = alert.present?
            data[:availability_alert_unsubscribe_url] = alert ? store_availability_alert_path(alert) : nil
          elsif product.available?
            data[:compare_url] = store_toggle_compare_path(product_id: product.public_id)
            data[:compared] = compared_ids.include?(product.public_id)
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
        addAllToCartUrl: store_add_all_to_cart_wishlist_path,
        compareCount: compare_product_count,
        wishlistImportCompareUrl: store_import_wishlist_compare_path,
        wishlistImportableCount: wishlist_importable_compare_count(compared_ids),
        filters: wishlist_filters_props,
        totalCount: total_count,
        filteredCount: items.size,
        savedFilterPresets: serialize_wishlist_filter_presets,
        saveFilterPresetUrl: store_wishlist_filter_presets_path
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
      all_items = Commerce::WishlistItem.where(user: user).includes(:product, :variant).order(created_at: :desc).to_a
      total_count = all_items.size
      items = sort_wishlist_items(filter_wishlist_items(all_items))

      render inertia: "Commerce/Wishlist/Public", props: {
        owner: user.display_name || user.username,
        products: items.map do |item|
          product = item.product
          data = serialize_product_list_item(product)
          if product.coming_soon?
            data[:url] = preview_store_product_path(product)
            data[:coming_soon] = true
            data[:available_at_label] = product.available_at ? l(product.available_at, format: :short) : nil
            data[:coming_soon_label] = product.coming_soon_label
          end
          data.merge(saved_variant_name: item.variant&.name, note: item.note.to_s)
        end,
        filters: wishlist_filters_props,
        totalCount: total_count,
        filteredCount: items.size
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
      product = Commerce::Product.active.find_by!(public_id: params[:product_id])
      unless product.available? || product.coming_soon?
        return redirect_to store_wishlist_path, alert: "商品不可编辑备注。"
      end
      result = Commerce::UpdateWishlistNote.call(user: current_user, product: product, note: params[:note])

      if result.success?
        redirect_to store_wishlist_path, notice: "备注已保存。"
      else
        redirect_to store_wishlist_path, alert: service_error_message(result)
      end
    end

    private

    def wishlist_filters_props
      {
        in_stock: params[:in_stock] == "1",
        on_sale: params[:on_sale] == "1",
        coming_soon: params[:coming_soon] == "1",
        sort: params[:sort].presence || "newest"
      }
    end

    def filter_wishlist_items(items)
      list = items
      if params[:in_stock] == "1"
        list = list.select do |item|
          product = item.product
          next false if product.coming_soon?

          variant = item.variant
          variant ? variant.in_stock? : product.in_stock?
        end
      end
      list = list.select { |item| item.product.on_sale? } if params[:on_sale] == "1"
      list = list.select { |item| item.product.coming_soon? } if params[:coming_soon] == "1"
      list
    end

    def sort_wishlist_items(items)
      case params[:sort]
      when "price_asc"
        items.sort_by { |item| item.variant&.price_cents || item.product.price_cents }
      when "price_desc"
        items.sort_by { |item| -(item.variant&.price_cents || item.product.price_cents) }
      when "name"
        items.sort_by { |item| item.product.name }
      else
        items
      end
    end

    def serialize_wishlist_filter_presets
      share_token = Commerce::EnsureWishlistShareToken.call(user: current_user).value&.dig(:token)

      current_user.store_wishlist_filter_presets.recent.limit(10).map do |preset|
        filters = preset.filters.symbolize_keys
        query = {
          in_stock: truthy_filter?(filters[:in_stock]) ? "1" : nil,
          on_sale: truthy_filter?(filters[:on_sale]) ? "1" : nil,
          coming_soon: truthy_filter?(filters[:coming_soon]) ? "1" : nil,
          sort: filters[:sort].presence
        }.compact
        {
          id: preset.id,
          name: preset.name,
          url: store_wishlist_path(query),
          public_share_url: share_token ? store_public_wishlist_url(share_token, query) : nil,
          delete_url: store_wishlist_filter_preset_path(preset)
        }
      end
    end

    def truthy_filter?(value)
      value == true || value == "1" || value == "true"
    end
  end
end
