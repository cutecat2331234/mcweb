# frozen_string_literal: true

module Community
  class FormatPostBody < ApplicationService
    WHITELIST = Website::BlockSanitizer::WHITELIST.merge(
      "img" => %w[src alt title width height class loading]
    )
    MENTION_PATTERN = /@([a-zA-Z0-9_]{3,32})/

    def initialize(body:)
      @body = body.to_s
    end

    def call
      placeholders = {}
      text = @body.dup

      text = text.gsub(/```(\w*)\n([\s\S]*?)```/) do
        token = placeholder_token(placeholders, "CODE")
        lang = Regexp.last_match(1)
        code = Regexp.last_match(2)
        lang_attr = lang.present? ? %( data-lang="#{ERB::Util.html_escape(lang)}") : ""
        placeholders[token] = %(<pre class="code-block"><code#{lang_attr}>#{ERB::Util.html_escape(code)}</code></pre>)
        token
      end

      text = text.gsub(/\|\|(.+?)\|\|/m) do
        token = placeholder_token(placeholders, "SPOILER")
        placeholders[token] = %(<span class="spoiler">#{ERB::Util.html_escape(Regexp.last_match(1))}</span>)
        token
      end

      text = text.gsub(/!\[([^\]]*)\]\((https?:\/\/[^)]+)\)/) do
        token = placeholder_token(placeholders, "IMG")
        alt = Regexp.last_match(1)
        url = Regexp.last_match(2)
        placeholders[token] = %(<img src="#{ERB::Util.html_escape(url)}" alt="#{ERB::Util.html_escape(alt)}" loading="lazy" class="post-image" />)
        token
      end

      text = text.gsub(MENTION_PATTERN) do
        username = Regexp.last_match(1)
        token = placeholder_token(placeholders, "MENTION")
        placeholders[token] = %(<a href="/forum/users/#{username}" class="mention">@#{username}</a>)
        token
      end

      html = markdown_to_html(text)
      sanitized = Sanitize.fragment(html, WHITELIST)

      placeholders.each { |token, replacement| sanitized = sanitized.gsub(token, replacement) }

      ServiceResult.success(sanitized)
    end

    private

    def placeholder_token(placeholders, prefix)
      "MCWEB#{prefix}#{placeholders.size}END"
    end

    def markdown_to_html(text)
      lines = text.split(/\r\n|\r|\n/)
      html_lines = []
      in_list = false

      lines.each do |line|
        if (match = line.match(/\A(#+)\s+(.+)\z/))
          html_lines << "</ul>" if in_list
          in_list = false
          level = [ match[1].length, 6 ].min
          html_lines << "<h#{level}>#{ERB::Util.html_escape(match[2])}</h#{level}>"
        elsif (match = line.match(/\A[-*]\s+(.+)\z/))
          html_lines << "<ul>" unless in_list
          in_list = true
          html_lines << "<li>#{inline_format(match[1])}</li>"
        elsif line.strip.empty?
          html_lines << "</ul>" if in_list
          in_list = false
          html_lines << "<br>"
        else
          html_lines << "</ul>" if in_list
          in_list = false
          html_lines << inline_format(line)
        end
      end
      html_lines << "</ul>" if in_list

      html_lines.join("\n")
    end

    def inline_format(text)
      escaped = ERB::Util.html_escape(text)
      escaped = escaped.gsub(/\*\*(.+?)\*\*/, '<strong>\1</strong>')
      escaped = escaped.gsub(/\*(.+?)\*/, '<em>\1</em>')
      escaped = escaped.gsub(/`([^`]+)`/, '<code>\1</code>')
      escaped.gsub(/\[([^\]]+)\]\((https?:\/\/[^)]+)\)/, '<a href="\2" rel="nofollow noopener">\1</a>')
    end
  end
end
