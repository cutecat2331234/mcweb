# frozen_string_literal: true

module Commerce
  class CompareController < ApplicationController
    def show
      ids = Array(session[:compare_product_ids])
      products_by_id = Commerce::Product.available.where(public_id: ids).includes(:variants, :category).index_by(&:public_id)
      products = ids.filter_map { |id| products_by_id[id] }

      render inertia: "Commerce/Compare/Show", props: {
        products: products.map { |product| serialize_compare_product(product) },
        compareCount: ids.size
      }
    end

    def toggle
      product = Commerce::Product.available.find_by!(public_id: params[:product_id])
      result = Commerce::ToggleCompare.call(session: session, product: product)

      if result.success?
        notice = result.value[:compared] ? "已加入对比。" : "已从对比移除。"
        redirect_back fallback_location: store_compare_path, notice: notice
      else
        redirect_back fallback_location: store_product_path(product), alert: service_error_message(result)
      end
    end

    def clear
      session[:compare_product_ids] = []
      redirect_to store_compare_path, notice: "对比列表已清空。"
    end

    private

    def serialize_compare_product(product)
      avg = product.reviews.published.average(:rating)&.round(1)
      {
        id: product.public_id,
        name: product.name,
        url: store_product_path(product),
        price_label: format_price(product),
        category_name: product.category&.name,
        in_stock: product.in_stock?,
        average_rating: avg,
        view_count: product.view_count,
        variants: product.variants.map { |variant| serialize_variant(variant, product) },
        toggle_url: store_toggle_compare_path(product_id: product.public_id)
      }
    end
  end
end
