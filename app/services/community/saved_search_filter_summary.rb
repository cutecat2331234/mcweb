# frozen_string_literal: true

module Community
  class SavedSearchFilterSummary
    VALUE_LABELS = {
      solved: { "solved" => "已解决", "unsolved" => "未解决" },
      locked: { "locked" => "已锁定", "unlocked" => "未锁定" },
      pinned: { "pinned" => "已置顶", "unpinned" => "未置顶" },
      wiki: { "wiki" => "Wiki 主题", "nonwiki" => "非 Wiki" },
      featured: { "featured" => "精选主题" },
      announcement: { "announcement" => "公告" },
      assigned: { "assigned" => "已分配", "unassigned" => "未分配" },
      unlisted: { "unlisted" => "未列出", "listed" => "已列出" },
      archived: { "archived" => "已归档", "active" => "未归档" },
      mine: { "mine" => "我的主题" },
      scope: {
        "bookmarks" => "我的收藏",
        "watching" => "正在关注",
        "unread" => "未读"
      },
      poll: { "poll" => "含投票" },
      noreplies: { "noreplies" => "无回复" },
      images: { "images" => "含图片" },
      topic_sort: { "recent" => "主题：最新", "oldest" => "主题：最早" },
      post_sort: { "recent" => "帖子：最新", "oldest" => "帖子：最早" },
      title_only: { "1" => "仅标题", "true" => "仅标题" },
      posts_only: { "1" => "仅帖子", "true" => "仅帖子" }
    }.freeze

    def self.call(saved_search)
      new(saved_search).labels
    end

    def initialize(saved_search)
      @saved_search = saved_search
      @filters = saved_search.filters.symbolize_keys
    end

    def labels
      chips = []
      query = @saved_search.query.to_s.strip
      chips << "关键词：#{query}" if query.present?

      append_lookup_label(chips, :section, "分区") { Community::Section.find_by(slug: @filters[:section])&.name }
      append_lookup_label(chips, :category, "分类") { Community::Category.find_by(slug: @filters[:category])&.name }
      append_lookup_label(chips, :tag, "标签") { Community::Tag.find_by(slug: @filters[:tag])&.name }

      append_value_label(chips, :author, "作者")
      append_value_label(chips, :assignee, "负责人")
      append_value_label(chips, :created_after, "起始于")
      append_value_label(chips, :created_before, "截止于")

      VALUE_LABELS.each_key do |key|
        append_mapped_label(chips, key)
      end

      chips
    end

  private

    def append_lookup_label(chips, key, prefix)
      value = @filters[key].presence
      return if value.blank?

      name = yield
      chips << "#{prefix}：#{name || value}"
    end

    def append_value_label(chips, key, prefix)
      value = @filters[key].presence
      return if value.blank?

      chips << "#{prefix}：#{value}"
    end

    def append_mapped_label(chips, key)
      value = @filters[key].presence
      return if value.blank?

      label = VALUE_LABELS[key]&.[](value.to_s) || value
      chips << label
    end
  end
end
