# frozen_string_literal: true

module Commerce
  class CategoriesController < ApplicationController
    def show
      category = Commerce::Category.find_by!(slug: params[:slug])
      scope = Commerce::Product.includes(:category).available.where(store_category_id: category.id)
      scope = scope.with_stock if params[:in_stock] == "1"
      scope = scope.on_sale if params[:on_sale] == "1"
      if params[:q].present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
        scope = scope.where("name ILIKE ? OR slug ILIKE ?", q, q)
      end
      scope = case params[:sort]
      when "price_asc" then scope.order(price_cents: :asc)
      when "price_desc" then scope.order(price_cents: :desc)
      when "popular" then scope.order(view_count: :desc, created_at: :desc)
      else scope.order(created_at: :desc)
      end

      @pagy, products = pagy(scope, limit: 20)

      render inertia: "Commerce/Categories/Show", props: {
        category: {
          slug: category.slug,
          name: category.name,
          description: category.description,
          icon: category.icon,
          color_hex: category.color_hex,
          seo_title: category.seo["title"].presence || category.name,
          seo_description: category.seo["description"].presence || category.description,
          rss_url: store_category_rss_path(category.slug)
        },
        products: products.map { |product| serialize_product_list_item(product) },
        pagination: pagy_props(@pagy),
        query: params[:q].to_s,
        filters: {
          in_stock: params[:in_stock] == "1",
          on_sale: params[:on_sale] == "1",
          sort: params[:sort].to_s
        }
      }
    end
  end
end
