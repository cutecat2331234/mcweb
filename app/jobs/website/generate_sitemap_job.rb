# frozen_string_literal: true

module Website
  class GenerateSitemapJob < ApplicationJob
    queue_as :website

    def perform
      pages = Website::Page.where(status: "published").pluck(:slug, :updated_at)
      articles = Website::Article.where(status: "published").pluck(:slug, :updated_at, :article_type)

      sitemap_path = Rails.root.join("public", "sitemap.xml")
      File.write(sitemap_path, build_sitemap(pages, articles))
    end

    private

    def build_sitemap(pages, articles)
      host = Rails.application.routes.default_url_options[:host] || "localhost"
      entries = []

      pages.each do |slug, updated_at|
        entries << url_entry("https://#{host}/#{slug}", updated_at)
      end

      articles.each do |slug, updated_at, article_type|
        entries << url_entry("https://#{host}/#{article_type}/#{slug}", updated_at)
      end

      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        #{entries.join("\n")}
        </urlset>
      XML
    end

    def url_entry(loc, updated_at)
      lastmod = updated_at&.iso8601 || Time.current.iso8601
      "  <url><loc>#{loc}</loc><lastmod>#{lastmod}</lastmod></url>"
    end
  end
end
