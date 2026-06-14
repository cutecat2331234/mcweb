# frozen_string_literal: true

module Community
  class RssController < ApplicationController
    def latest
      topics = Community::Topic.where(status: :published).sorted("activity").limit(30)
      render xml: build_feed(topics, title: "Mcweb 论坛最新", url: forum_latest_url), content_type: "application/rss+xml"
    end

    def section
      section = Community::Section.find_by!(slug: params[:id])
      topics = section.topics.where(status: :published).sorted("activity").limit(30)
      render xml: build_feed(topics, title: "#{section.name} - Mcweb 论坛", url: forum_section_url(section)), content_type: "application/rss+xml"
    end

    private

    def build_feed(topics, title:, url:)
      items = topics.map { |topic| feed_item(topic) }.join("\n")
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>#{escape_xml(title)}</title>
            <link>#{escape_xml(url)}</link>
            <description>Mcweb Community Forum</description>
            <lastBuildDate>#{Time.current.rfc2822}</lastBuildDate>
            #{items}
          </channel>
        </rss>
      XML
    end

    def feed_item(topic)
      link = forum_topic_url(topic)
      pub_date = (topic.last_posted_at || topic.created_at).rfc2822
      description = escape_xml(topic.posts.first&.body&.truncate(300).to_s)
      <<~XML
        <item>
          <title>#{escape_xml(topic.title)}</title>
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
