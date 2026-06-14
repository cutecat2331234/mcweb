# frozen_string_literal: true

module Website
  class HomeController < ApplicationController
    skip_installation_guard only: :index

    def index
      featured = begin
        Website::Article.published.order(published_at: :desc).limit(6)
      rescue ActiveRecord::StatementInvalid
        []
      end

      featured_products = begin
        Commerce::Product.available.where(featured: true).order(created_at: :desc).limit(6)
      rescue ActiveRecord::StatementInvalid
        []
      end

      render inertia: "Website/Home", props: {
        featuredArticles: featured.map { |article| serialize_article(article) },
        featuredProducts: featured_products.map { |product| serialize_product_list_item(product) }
      }
    end
  end
end
