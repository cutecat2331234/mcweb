# frozen_string_literal: true

module Website
  class HomeController < ApplicationController
    def index
      featured = if FeatureFlags.enabled?(:website_blog)
        begin
          Website::Article.published.order(published_at: :desc).limit(6)
        rescue ActiveRecord::StatementInvalid
          []
        end
      else
        []
      end

      featured_products = if FeatureFlags.enabled?(:store)
        begin
          Commerce::Product.available.where(featured: true).order(created_at: :desc).limit(6)
        rescue ActiveRecord::StatementInvalid
          []
        end
      else
        []
      end

      render inertia: "Website/Home", props: {
        featuredArticles: featured.map { |article| serialize_article(article) },
        featuredProducts: featured_products.map { |product| serialize_product_list_item(product) }
      }
    end
  end
end
