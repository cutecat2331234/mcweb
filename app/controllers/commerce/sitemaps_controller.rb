# frozen_string_literal: true

module Commerce
  class SitemapsController < ApplicationController
    def index
      products = Commerce::StoreFeatures.visible_products_scope(
        Commerce::Product.available.order(updated_at: :desc).limit(500)
      )
      urls = products.map do |product|
        <<~XML
          <url>
            <loc>#{ERB::Util.html_escape(store_product_url(product))}</loc>
            <lastmod>#{product.updated_at.iso8601}</lastmod>
            <changefreq>weekly</changefreq>
            <priority>0.7</priority>
          </url>
        XML
      end.join

      categories = Commerce::Category.ordered
      category_urls = categories.map do |category|
        <<~XML
          <url>
            <loc>#{ERB::Util.html_escape(store_category_url(category))}</loc>
            <changefreq>weekly</changefreq>
            <priority>0.5</priority>
          </url>
        XML
      end.join

      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          <url>
            <loc>#{ERB::Util.html_escape(store_products_url)}</loc>
            <changefreq>daily</changefreq>
            <priority>0.8</priority>
          </url>
          #{category_urls}
          #{urls}
        </urlset>
      XML

      render xml: xml, content_type: "application/xml"
    end
  end
end
