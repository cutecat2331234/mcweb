# frozen_string_literal: true

module Website
  class HomeController < ApplicationController
    def index
      feature_state = FeatureFlags.frontend_hash
      unless logged_in?
        fresh_when(
          etag: [
            Website::HomeCache.version,
            Frontend::WebsiteRenderer.cache_key,
            I18n.locale,
            feature_state
          ],
          public: false
        )
        return if performed?
      end
      payload = Website::HomeCache.fetch(
        locale: I18n.locale,
        feature_state:
      ) { build_home_payload(feature_state) }
      Frontend::WebsiteRenderer.call(
        controller: self,
        component: payload.fetch(:component),
        props: payload.fetch(:props)
      )
    end

    private

    def build_home_payload(feature_state)
      cms_home = Website::Page.cms_home.first
      return cms_home_payload(cms_home) if cms_home

      featured = if feature_state.fetch("website_blog")
        Website::Article.published.order(published_at: :desc).limit(6).to_a
      else
        []
      end
      featured_products = if feature_state.fetch("store")
        Commerce::StoreFeatures.visible_products_scope(
          Commerce::Product.available
            .where(featured: true)
            .order(created_at: :desc)
            .limit(6)
        )
      else
        []
      end
      featured_products = prepare_product_list(featured_products)

      {
        component: "Website/Home",
        props: {
          featuredArticles: featured.map { |article| serialize_article(article) },
          featuredProducts: featured_products.map do |product|
            serialize_product_list_item(product)
          end
        }
      }
    rescue ActiveRecord::StatementInvalid
      {
        component: "Website/Home",
        props: { featuredArticles: [], featuredProducts: [] }
      }
    end

    def cms_home_payload(page)
      blocks_result = Website::SerializePageBlocks.call(page: page)
      seo_result = Website::ResolveSeo.call(record: page)

      {
        component: "Website/Pages/Show",
        props: {
          page: { title: page.title, slug: page.slug },
          blocks: blocks_result.value,
          seo: seo_result.value
        }
      }
    end
  end
end
