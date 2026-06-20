# frozen_string_literal: true

module Commerce
  class CompareController < ApplicationController
    include Commerce::WishlistCompareImportable

    before_action :require_login, only: %i[share import_wishlist]

    def show
      ids = Array(session[:compare_product_ids])
      visible_scope = Commerce::StoreFeatures.visible_products_scope(Commerce::Product.active.where(public_id: ids))
      active_ids = visible_scope.pluck(:public_id)
      session[:compare_product_ids] = ids.filter { |id| active_ids.include?(id) }
      ids = session[:compare_product_ids]

      products_by_id = visible_scope.includes(:variants, :category).index_by(&:public_id)
      products = ids.filter_map { |id| products_by_id[id] }
      share_url = compare_share_url_for(current_user, ids)

      render inertia: "Commerce/Compare/Show", props: {
        products: products.map { |product| serialize_compare_product(product) },
        compareCount: products.size,
        compareMaxItems: Commerce::ToggleCompare.compare_max_items,
        shareUrl: share_url,
        wishlistImportUrl: logged_in? ? store_import_wishlist_compare_path : nil,
        wishlistImportableCount: logged_in? ? wishlist_importable_compare_count(ids) : 0
      }
    end

    def toggle
      product = Commerce::Product.active.find_by!(public_id: params[:product_id])
      unless Commerce::StoreFeatures.product_visible?(product)
        return redirect_back fallback_location: store_products_path, alert: t("mcweb.flash.compare_product_invalid")
      end
      unless product.available? || product.coming_soon?
        return redirect_back fallback_location: store_products_path, alert: t("mcweb.flash.compare_product_invalid")
      end

      result = Commerce::ToggleCompare.call(session: session, product: product)

      if result.success?
        notice = result.value[:compared] ? t("mcweb.flash.compare_toggled_on") : t("mcweb.flash.compare_toggled_off")
        redirect_back fallback_location: compare_fallback_path(product), notice: notice
      else
        redirect_back fallback_location: compare_fallback_path(product), alert: service_error_message(result)
      end
    end

    def clear
      session[:compare_product_ids] = []
      redirect_to store_compare_path, notice: t("mcweb.flash.compare_cleared")
    end

    def share
      ids = Array(session[:compare_product_ids])
      return redirect_to store_compare_path, alert: t("mcweb.flash.compare_empty") if ids.empty?

      result = Commerce::EnsureCompareShareToken.call(user: current_user, product_ids: ids)
      if result.success?
        redirect_to store_compare_path, notice: t("mcweb.flash.compare_share_created")
      else
        redirect_to store_compare_path, alert: service_error_message(result)
      end
    end

    def import_wishlist
      result = Commerce::AddWishlistToCompare.call(user: current_user, session: session)

      if result.success?
        notice = t("mcweb.flash.compare_bulk_added", count: result.value[:added])
        notice += t("mcweb.flash.compare_bulk_skipped", items: result.value[:skipped].join(I18n.t("mcweb.commerce.list_separator"))) if result.value[:skipped].any?
        redirect_back fallback_location: store_compare_path, notice: notice
      else
        redirect_back fallback_location: store_compare_path, alert: service_error_message(result)
      end
    end

    def public_show
      user = User.find_by!(compare_share_token: params[:token])
      ids = Array(user.compare_product_ids)
      products_by_id = Commerce::StoreFeatures.visible_products_scope(
        Commerce::Product.active.where(public_id: ids)
      ).includes(:variants, :category).index_by(&:public_id)
      products = ids.filter_map { |id| products_by_id[id] }

      render inertia: "Commerce/Compare/Public", props: {
        owner: user.display_name.presence || user.username,
        products: products.map { |product| serialize_compare_product(product) }
      }
    end

    private

    def compare_share_url_for(user, ids)
      return nil unless user && ids.any?

      result = Commerce::EnsureCompareShareToken.call(user: user, product_ids: ids)
      result.success? ? store_public_compare_url(result.value[:token]) : nil
    end

    def serialize_compare_product(product)
      avg = product.reviews.published.average(:rating)&.round(1)
      {
        id: product.public_id,
        db_id: product.id,
        name: product.name,
        url: product.coming_soon? ? preview_store_product_path(product) : store_product_path(product),
        coming_soon: product.coming_soon?,
        price_label: format_price(product),
        category_name: product.category&.name,
        in_stock: product.in_stock?,
        average_rating: avg,
        view_count: product.view_count,
        variants: product.variants.map { |variant| serialize_variant(variant, product) },
        toggle_url: store_toggle_compare_path(product_id: product.public_id),
        add_to_cart_url: store_cart_path
      }
    end

    def compare_fallback_path(product)
      product.coming_soon? ? preview_store_product_path(product) : store_product_path(product)
    end
  end
end
