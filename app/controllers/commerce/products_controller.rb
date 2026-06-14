# frozen_string_literal: true

module Commerce
  class ProductsController < ApplicationController
    def index
      scope = Commerce::Product.includes(:category).available
      if params[:q].present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
        scope = scope.where("name ILIKE ? OR slug ILIKE ?", q, q)
      end
      scope = case params[:sort]
              when "price_asc" then scope.order(price_cents: :asc)
              when "price_desc" then scope.order(price_cents: :desc)
              else scope.order(created_at: :desc)
              end

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
        query: params[:q].to_s,
        sort: params[:sort].to_s.presence || "newest",
        pagination: pagy_props(@pagy)
      }
    end

    def show
      product = Commerce::Product.available.includes(:variants, :category).find_by!(public_id: params[:id])
      reviews = product.reviews.published.includes(:user).order(created_at: :desc).limit(20)
      avg = product.reviews.published.average(:rating)&.round(1)
      wishlisted = logged_in? && Commerce::WishlistItem.exists?(user: current_user, product: product)

      render inertia: "Commerce/Products/Show", props: {
        product: serialize_product_detail(product, wishlisted: wishlisted, reviews: reviews, average_rating: avg),
        addToCartUrl: store_cart_path,
        wishlistUrl: wishlist_store_product_path(product),
        reviewUrl: store_reviews_path(product),
        loggedIn: logged_in?
      }
    end
  end
end
