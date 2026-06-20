# frozen_string_literal: true

module Community
  class SitemapsController < ApplicationController
    include Community::SectionVisibility

    def index
      topics = apply_login_required_topic_scope(Community::Topic.published_listed).order(updated_at: :desc).limit(500)
      urls = topics.map do |topic|
        <<~XML
          <url>
            <loc>#{ERB::Util.html_escape(forum_topic_url(topic))}</loc>
            <lastmod>#{topic.updated_at.iso8601}</lastmod>
            <changefreq>weekly</changefreq>
            <priority>0.6</priority>
          </url>
        XML
      end.join

      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
          #{urls}
        </urlset>
      XML

      render xml: xml, content_type: "application/xml"
    end
  end
end
