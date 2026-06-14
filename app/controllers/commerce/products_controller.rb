# frozen_string_literal: true

module Commerce
  class ProductsController < ApplicationController
    def index
      scope = Commerce::Product.includes(:category).available.order(created_at: :desc)
      if params[:category].present?
        category = Commerce::Category.find_by!(slug: params[:category])
        scope = scope.where(store_category_id: category.id)
      end

      @pagy, products = pagy(scope, limit: 20)
      categories = Commerce::Category.ordered

      render inertia: "Commerce/Products/Index", props: {
        products: products.map { |product| serialize_product_list_item(product) },
        categories: categories.map { |category| serialize_category(category) },
        activeCategory: params[:category],
        pagination: pagy_props(@pagy)
      }
    end

    def show
      product = Commerce::Product.available.includes(:variants, :category).find_by!(public_id: params[:id])

      render inertia: "Commerce/Products/Show", props: {
        product: serialize_product_detail(product),
        addToCartUrl: store_cart_path
      }
    end
  end
end
