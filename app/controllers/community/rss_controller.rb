# frozen_string_literal: true

module Community
  class RssController < ApplicationController
    def latest
      topics = Community::Topic.published_listed.sorted("activity").limit(30)
      render xml: build_feed(topics, title: "Mcweb 论坛最新", url: forum_latest_url), content_type: "application/rss+xml"
    end

    def section
      section = Community::Section.find_by!(slug: params[:id])
      topics = section.topics.published_listed.sorted("activity").limit(30)
      render xml: build_feed(topics, title: "#{section.name} - Mcweb 论坛", url: forum_section_url(section)), content_type: "application/rss+xml"
    end

    def tag
      tag = Community::Tag.find_by!(slug: params[:slug])
      topic_ids = tag.topics.published_listed.pluck(:id)
      topics = Community::Topic.where(id: topic_ids).sorted("activity").limit(30)
      render xml: build_feed(topics, title: "标签 #{tag.name} - Mcweb 论坛", url: forum_tag_url(tag.slug)), content_type: "application/rss+xml"
    end

    def category
      category = Community::Category.find_by!(slug: params[:slug])
      section_ids = category.sections.pluck(:id)
      topics = Community::Topic.published_listed.where(forum_section_id: section_ids).sorted("activity").limit(30)
      render xml: build_feed(topics, title: "#{category.name} - Mcweb 论坛", url: forum_category_url(slug: category.slug)), content_type: "application/rss+xml"
    end

    def saved_search
      search_id = Community::SavedSearchRssToken.verify(params[:token])
      search = Community::SavedSearch.find(search_id)
      raise ActiveRecord::RecordNotFound unless search.id.to_s == params[:id].to_s

      topics = Community::SavedSearchMatcher.new(search).matching_topics.limit(30).to_a
      url = forum_search_path(Community::SavedSearchPresenter.url_params(search))
      render xml: build_feed(topics, title: "#{search.name} - 保存的搜索", url: url), content_type: "application/rss+xml"
    rescue Community::SavedSearchRssToken::InvalidToken, ActiveRecord::RecordNotFound
      head :not_found
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
