# frozen_string_literal: true

module Website
  class HomeController < ApplicationController
    def index
      cms_home = Website::Page.cms_home.first
      if cms_home
        return render_cms_page(cms_home)
      end

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
          Commerce::StoreFeatures.visible_products_scope(
            Commerce::Product.available.where(featured: true).order(created_at: :desc).limit(6)
          )
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

    private

    def render_cms_page(page)
      blocks_result = Website::SerializePageBlocks.call(page: page)
      seo_result = Website::ResolveSeo.call(record: page)

      render inertia: "Website/Pages/Show", props: {
        page: { title: page.title, slug: page.slug },
        blocks: blocks_result.value,
        seo: seo_result.value
      }
    end
  end
end
