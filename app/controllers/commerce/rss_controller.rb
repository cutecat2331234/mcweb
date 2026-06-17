# frozen_string_literal: true

module Commerce
  class RssController < ApplicationController
    def latest
      products = Commerce::Product.available.order(created_at: :desc).limit(30)
      render xml: build_feed(products, title: "Mcweb 商城最新商品", url: store_products_path), content_type: "application/rss+xml"
    end

    def category
      category = Commerce::Category.find_by!(slug: params[:slug])
      products = Commerce::Product.available.where(store_category_id: category.id).order(created_at: :desc).limit(30)
      render xml: build_feed(products, title: "#{category.name} - Mcweb 商城", url: store_category_path(category.slug)), content_type: "application/rss+xml"
    end

    private

    def build_feed(products, title:, url:)
      items = products.map { |product| feed_item(product) }.join("\n")
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>#{escape_xml(title)}</title>
            <link>#{escape_xml(url)}</link>
            <description>Mcweb Store</description>
            <lastBuildDate>#{Time.current.rfc2822}</lastBuildDate>
            #{items}
          </channel>
        </rss>
      XML
    end

    def feed_item(product)
      link = store_product_url(product)
      pub_date = product.created_at.rfc2822
      description = escape_xml(product.description.to_s.truncate(300))
      <<~XML
        <item>
          <title>#{escape_xml(product.name)}</title>
          <link>#{escape_xml(link)}</link>
          <pubDate>#{pub_date}</pubDate>
          <description>#{description}</description>
        </item>
      XML
    end

    def escape_xml(text)
      ERB::Util.html_escape(text.to_s)
    end
  end
end
