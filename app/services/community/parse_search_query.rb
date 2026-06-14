# frozen_string_literal: true

module Community
  class ParseSearchQuery < ApplicationService
    IN_PATTERN = /\bin:(\S+)/i
    TAG_PATTERN = /\btag:(\S+)/i
    IS_SOLVED_PATTERN = /\bis:(solved|unsolved)\b/i
    AUTHOR_AT_PATTERN = /\B@([a-zA-Z0-9_]+)/
    AUTHOR_COLON_PATTERN = /\bauthor:([a-zA-Z0-9_]+)/i

    def initialize(query:)
      @query = query.to_s.strip
    end

    def call
      section_slug = nil
      tag_slug = nil
      solved_filter = nil
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

      if (match = text.match(IS_SOLVED_PATTERN))
        solved_filter = match[1].downcase
        text = text.gsub(match[0], "").strip
      end

      if (match = text.match(AUTHOR_COLON_PATTERN))
        author = match[1]
        text = text.gsub(match[0], "").strip
      elsif (match = text.match(AUTHOR_AT_PATTERN))
        author = match[1]
        text = text.gsub(match[0], "").strip
      end

      ServiceResult.success(
        query: text.squish,
        section_slug: section_slug,
        tag_slug: tag_slug,
        solved_filter: solved_filter,
        author: author
      )
    end
  end
end
