# frozen_string_literal: true

module Community
  class ParseSearchQuery < ApplicationService
    IN_PATTERN = /\bin:(\S+)/i
    CATEGORY_PATTERN = /\bcategory:(\S+)/i
    TAG_PATTERN = /\btag:(\S+)/i
    IS_PATTERN = /\bis:(\S+)\b/i
    HAS_PATTERN = /\bhas:(\S+)\b/i
    AUTHOR_AT_PATTERN = /\B@([a-zA-Z0-9_]+)/
    AUTHOR_COLON_PATTERN = /\bauthor:([a-zA-Z0-9_]+)/i
    ASSIGNED_PATTERN = /\bassigned:([a-zA-Z0-9_]+)/i

    VALID_TOPIC_FLAGS = %w[solved unsolved locked unlocked pinned wiki featured announcement global unlisted archived mine assigned unassigned].freeze
    RESERVED_IN_SCOPES = %w[bookmarks watching unread title posts].freeze
    VALID_HAS_FLAGS = %w[poll noreplies images].freeze

    def initialize(query:)
      @query = query.to_s.strip
    end

    def call
      section_slug = nil
      category_slug = nil
      scope_filter = nil
      title_only_filter = nil
      posts_only_filter = nil
      tag_slug = nil
      topic_flags = {}
      has_flags = {}
      author = nil
      assignee = nil
      text = @query.dup

      if (match = text.match(IN_PATTERN))
        scope = match[1].downcase
        if scope == "title"
          title_only_filter = true
        elsif scope == "posts"
          posts_only_filter = true
        elsif RESERVED_IN_SCOPES.include?(scope)
          scope_filter = scope
        else
          section_slug = match[1]
        end
        text = text.gsub(match[0], "").strip
      end

      if (match = text.match(CATEGORY_PATTERN))
        category_slug = match[1]
        text = text.gsub(match[0], "").strip
      end

      if (match = text.match(TAG_PATTERN))
        tag_slug = match[1]
        text = text.gsub(match[0], "").strip
      end

      while (match = text.match(IS_PATTERN))
        flag = match[1].downcase
        topic_flags[flag] = true if VALID_TOPIC_FLAGS.include?(flag)
        text = text.gsub(match[0], "").strip
      end

      while (match = text.match(HAS_PATTERN))
        flag = match[1].downcase
        has_flags[flag] = true if VALID_HAS_FLAGS.include?(flag)
        text = text.gsub(match[0], "").strip
      end

      if (match = text.match(ASSIGNED_PATTERN))
        assignee = match[1].downcase
        text = text.gsub(match[0], "").strip
      end

      if (match = text.match(AUTHOR_COLON_PATTERN))
        author = match[1]
        text = text.gsub(match[0], "").strip
      elsif (match = text.match(AUTHOR_AT_PATTERN))
        author = match[1]
        text = text.gsub(match[0], "").strip
      end

      solved_filter = if topic_flags["solved"]
                        "solved"
      elsif topic_flags["unsolved"]
                        "unsolved"
      end

      announcement_filter = if topic_flags["announcement"] || topic_flags["global"]
                              "announcement"
      end

      ServiceResult.success(
        query: text.squish,
        section_slug: section_slug,
        category_slug: category_slug,
        tag_slug: tag_slug,
        solved_filter: solved_filter,
        locked_filter: topic_flags["locked"] ? "locked" : (topic_flags["unlocked"] ? "unlocked" : nil),
        pinned_filter: topic_flags["pinned"] ? "pinned" : nil,
        wiki_filter: topic_flags["wiki"] ? "wiki" : nil,
        featured_filter: topic_flags["featured"] ? "featured" : nil,
        announcement_filter: announcement_filter,
        unlisted_filter: topic_flags["unlisted"] ? "unlisted" : nil,
        archived_filter: topic_flags["archived"] ? "archived" : nil,
        assigned_filter: if topic_flags["assigned"]
                           "assigned"
                         elsif topic_flags["unassigned"]
                           "unassigned"
                         end,
        assignee_filter: assignee,
        mine_filter: topic_flags["mine"] ? "mine" : nil,
        scope_filter: scope_filter,
        poll_filter: has_flags["poll"] ? "poll" : nil,
        noreplies_filter: has_flags["noreplies"] ? "noreplies" : nil,
        images_filter: has_flags["images"] ? "images" : nil,
        title_only_filter: title_only_filter,
        posts_only_filter: posts_only_filter,
        author: author
      )
    end
  end
end
