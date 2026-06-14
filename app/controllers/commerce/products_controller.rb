# frozen_string_literal: true

module Commerce
  class ProductsController < ApplicationController
    def index
      @pagy, products = pagy(
        Commerce::Product.includes(:category).available.order(created_at: :desc),
        limit: 20
      )

      render inertia: "Commerce/Products/Index", props: {
        products: products.map { |product| serialize_product_list_item(product) },
        pagination: pagy_props(@pagy)
      }
    end

    def show
      product = Commerce::Product.available.find_by!(public_id: params[:id])

      render inertia: "Commerce/Products/Show", props: {
        product: serialize_product_detail(product),
        addToCartUrl: store_cart_path
      }
    end
  end
end
