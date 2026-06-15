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

    def ad_hoc_search
      permitted = verified_ad_hoc_search_params
      result = Community::BuildAdHocSearchTopicScope.call(params: permitted, user: current_user)
      topics = result.value[:scope].limit(30).to_a
      query = permitted["q"].to_s
      title = query.present? ? "搜索：#{query}" : "论坛搜索"
      url = forum_search_url(permitted.symbolize_keys)
      render xml: build_feed(topics, title: title, url: url), content_type: "application/rss+xml"
    rescue Community::SearchRssToken::InvalidToken
      head :not_found
    end

    def ad_hoc_search_opml
      permitted = verified_ad_hoc_search_params
      query = permitted["q"].to_s
      title = query.present? ? "搜索：#{query}" : "论坛搜索"
      rss_url = forum_search_rss_url(permitted.symbolize_keys.merge(token: Community::SearchRssToken.generate(permitted)))
      html_url = forum_search_url(permitted.symbolize_keys)
      outline = opml_outline(title, rss_url: rss_url, html_url: html_url)
      render xml: wrap_opml(title: title, outlines: outline), content_type: "application/xml"
    rescue Community::SearchRssToken::InvalidToken
      head :not_found
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

    def saved_searches_opml
      user_id = Community::SavedSearchOpmlToken.verify(params[:token])
      user = User.find(user_id)
      searches = user.forum_saved_searches.recent.limit(50)
      render xml: build_opml(user, searches), content_type: "application/xml"
    rescue Community::SavedSearchOpmlToken::InvalidToken, ActiveRecord::RecordNotFound
      head :not_found
    end

    def search_histories_opml
      user_id = Community::SearchHistoryOpmlToken.verify(params[:token])
      user = User.find(user_id)
      render xml: build_search_histories_opml(user), content_type: "application/xml"
    rescue Community::SearchHistoryOpmlToken::InvalidToken, ActiveRecord::RecordNotFound
      head :not_found
    end

    def watching_opml
      user_id = Community::WatchingOpmlToken.verify(params[:token])
      user = User.find(user_id)
      render xml: build_watching_opml(user), content_type: "application/xml"
    rescue Community::WatchingOpmlToken::InvalidToken, ActiveRecord::RecordNotFound
      head :not_found
    end

    private

    def verified_ad_hoc_search_params
      permitted = Community::SearchRssToken.verify(params[:token])
      raise Community::SearchRssToken::InvalidToken if permitted != Community::SearchRssToken.normalize(params.except(:controller, :action, :token, :format))

      permitted
    end

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

    def build_opml(user, searches)
      outlines = searches.map do |search|
        rss_url = forum_saved_search_rss_url(id: search.id, token: Community::SavedSearchRssToken.generate(search))
        html_url = forum_search_url(Community::SavedSearchPresenter.url_params(search))
        opml_outline(search.name, rss_url: rss_url, html_url: html_url)
      end.join("\n")

      wrap_opml(title: "#{user.username} 的保存搜索", outlines: outlines)
    end

    def build_search_histories_opml(user)
      outlines = user.forum_search_histories.recent.limit(20).map do |history|
        params = history.rss_params
        token = Community::SearchRssToken.generate(params)
        title = history.query.presence || "筛选搜索"
        rss_url = forum_search_rss_url(params.symbolize_keys.merge(token: token))
        html_url = forum_search_url(history.url_params)
        opml_outline("#{title} (#{l(history.updated_at, format: :short)})", rss_url: rss_url, html_url: html_url)
      end.join("\n")

      wrap_opml(title: "#{user.username} 的搜索历史", outlines: outlines)
    end

    def build_watching_opml(user)
      outlines = []

      Community::Subscription.where(user: user, subscribable_type: "Community::Section").find_each do |sub|
        section = Community::Section.find_by(id: sub.subscribable_id)
        next unless section

        outlines << opml_outline(
          section.name,
          rss_url: forum_section_rss_url(id: section.slug),
          html_url: forum_section_url(section)
        )
      end

      Community::Subscription.where(user: user, subscribable_type: "Community::Tag").find_each do |sub|
        tag = Community::Tag.find_by(id: sub.subscribable_id)
        next unless tag

        outlines << opml_outline(
          "标签 #{tag.name}",
          rss_url: forum_tag_rss_url(slug: tag.slug),
          html_url: forum_tag_url(tag.slug)
        )
      end

      Community::Subscription.where(user: user, subscribable_type: "Community::Topic").find_each do |sub|
        topic = Community::Topic.find_by(id: sub.subscribable_id)
        next unless topic&.published?

        outlines << opml_outline(
          topic.title,
          rss_url: forum_topic_url(topic),
          html_url: forum_topic_url(topic)
        )
      end

      wrap_opml(title: "#{user.username} 的关注订阅", outlines: outlines.join("\n"))
    end

    def opml_outline(title, rss_url:, html_url:)
      <<~XML
        <outline type="rss" text="#{escape_xml(title)}" title="#{escape_xml(title)}" xmlUrl="#{escape_xml(rss_url)}" htmlUrl="#{escape_xml(html_url)}" />
      XML
    end

    def wrap_opml(title:, outlines:)
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head>
            <title>#{escape_xml(title)}</title>
            <dateCreated>#{Time.current.rfc2822}</dateCreated>
          </head>
          <body>
            #{outlines}
          </body>
        </opml>
      XML
    end
  end
end
