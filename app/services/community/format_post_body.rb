# frozen_string_literal: true

module Community
  class FormatPostBody < ApplicationService
    WHITELIST = Website::BlockSanitizer::WHITELIST
    MENTION_PATTERN = /@([a-zA-Z0-9_]{3,32})/

    def initialize(body:)
      @body = body.to_s
    end

    def call
      placeholders = {}
      text = @body.gsub(MENTION_PATTERN) do
        username = Regexp.last_match(1)
        token = "MCWEBMENTION#{placeholders.size}END"
        placeholders[token] = username
        token
      end

      html = markdown_to_html(text)
      sanitized = Sanitize.fragment(html, WHITELIST)

      placeholders.each do |token, username|
        sanitized = sanitized.gsub(
          token,
          %(<a href="/forum/users/#{username}" class="mention">@#{username}</a>)
        )
      end

      ServiceResult.success(sanitized)
    end

    private

    def markdown_to_html(text)
      escaped = ERB::Util.html_escape(text)
      escaped = escaped.gsub(/\*\*(.+?)\*\*/, '<strong>\1</strong>')
      escaped = escaped.gsub(/\*(.+?)\*/, '<em>\1</em>')
      escaped = escaped.gsub(/`([^`]+)`/, '<code>\1</code>')
      escaped = escaped.gsub(/\[([^\]]+)\]\((https?:\/\/[^)]+)\)/, '<a href="\2" rel="nofollow noopener">\1</a>')
      escaped.gsub(/\r\n|\r|\n/, "<br>")
    end
  end
end
