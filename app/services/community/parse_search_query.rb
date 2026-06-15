# frozen_string_literal: true

module Community
  class ParseSearchQuery < ApplicationService
    IN_PATTERN = /\bin:(\S+)/i
    TAG_PATTERN = /\btag:(\S+)/i
    IS_PATTERN = /\bis:(\S+)\b/i
    HAS_PATTERN = /\bhas:(\S+)\b/i
    AUTHOR_AT_PATTERN = /\B@([a-zA-Z0-9_]+)/
    AUTHOR_COLON_PATTERN = /\bauthor:([a-zA-Z0-9_]+)/i

    VALID_TOPIC_FLAGS = %w[solved unsolved locked unlocked pinned wiki featured announcement global unlisted].freeze
    VALID_HAS_FLAGS = %w[poll noreplies].freeze

    def initialize(query:)
      @query = query.to_s.strip
    end

    def call
      section_slug = nil
      tag_slug = nil
      topic_flags = {}
      has_flags = {}
      author = nil
      text = @query.dup

      if (match = text.match(IN_PATTERN))
        section_slug = match[1]
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
        tag_slug: tag_slug,
        solved_filter: solved_filter,
        locked_filter: topic_flags["locked"] ? "locked" : (topic_flags["unlocked"] ? "unlocked" : nil),
        pinned_filter: topic_flags["pinned"] ? "pinned" : nil,
        wiki_filter: topic_flags["wiki"] ? "wiki" : nil,
        featured_filter: topic_flags["featured"] ? "featured" : nil,
        announcement_filter: announcement_filter,
        unlisted_filter: topic_flags["unlisted"] ? "unlisted" : nil,
        poll_filter: has_flags["poll"] ? "poll" : nil,
        noreplies_filter: has_flags["noreplies"] ? "noreplies" : nil,
        author: author
      )
    end
  end
end
