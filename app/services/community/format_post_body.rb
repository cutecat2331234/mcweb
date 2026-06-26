# frozen_string_literal: true

module Community
  class FormatPostBody < ApplicationService
    WHITELIST = Website::BlockSanitizer::WHITELIST.merge(
      "img" => %w[src alt title width height class loading],
      "aside" => %w[class],
      "strong" => %w[class],
      "em" => %w[class],
      "del" => %w[class],
      "code" => %w[class data-lang],
      "pre" => %w[class],
      "p" => %w[class],
      "blockquote" => %w[class],
      "ul" => %w[class],
      "ol" => %w[class],
      "li" => %w[class],
      "br" => [],
      "table" => %w[class],
      "thead" => %w[class],
      "tbody" => %w[class],
      "tr" => %w[class],
      "th" => %w[class scope],
      "td" => %w[class],
      "div" => %w[class],
      "input" => %w[type checked disabled class],
      "hr" => %w[class],
      "sup" => %w[class id],
      "button" => %w[type class data-copy-target],
      "iframe" => %w[src width height frameborder allow allowfullscreen class loading title],
      "a" => %w[href rel class]
    )
    MENTION_PATTERN = /@([a-zA-Z0-9_]{3,32})/
    VIDEO_URL_PATTERN = %r{\Ahttps?://(?:www\.)?(?:youtube\.com/watch\?v=|youtu\.be/|vimeo\.com/)([\w-]+)\z}i

    def initialize(body:)
      @body = body.to_s
    end

    def call
      filtered = Community::FilterCensoredWords.call(text: @body)
      body = filtered.success? ? filtered.value : @body

      body, footnote_defs = extract_footnote_definitions(body)

      placeholders = {}
      text = body.dup
      footnote_used = []

      # XenForo BBCode -> Markdown equivalents (no-op when no BBCode tags present),
      # so the existing Markdown pipeline renders them.
      text = convert_bbcode(text)

      text = text.gsub(/\[\^([^\]]+)\]/) do
        label = Regexp.last_match(1)
        next Regexp.last_match(0) unless footnote_defs[label]

        footnote_used << label
        token = placeholder_token(placeholders, "FNREF")
        safe = ERB::Util.html_escape(label)
        placeholders[token] = %(<sup class="footnote-ref" id="fnref-#{safe}"><a href="#fn-#{safe}">#{safe}</a></sup>)
        token
      end

      text = text.gsub(/^([-*]\s+\[(?: |x|X)\]\s+.+)$/) do |line|
        match = line.match(/\A[-*]\s+\[( |x|X)\]\s+(.+)\z/)
        token = placeholder_token(placeholders, "TASK")
        checked = match[1].match?(/x/i) ? " checked disabled" : " disabled"
        placeholders[token] = %(<li class="task-item"><input type="checkbox"#{checked} /> #{ERB::Util.html_escape(match[2])}</li>)
        token
      end

      text = text.gsub(/^(-{3,}|\*{3,}|_{3,})\s*$/m) do
        token = placeholder_token(placeholders, "HR")
        placeholders[token] = '<hr class="post-hr" />'
        token
      end

      text = text.gsub(/\|\|(.+?)\|\|/m) do
        token = placeholder_token(placeholders, "SPOILER")
        placeholders[token] = %(<span class="spoiler">#{ERB::Util.html_escape(Regexp.last_match(1))}</span>)
        token
      end

      text = text.gsub(/(?:^\|[^|\n]+(?:\|[^|\n]+)+\|\s*$\r?\n?)+/) do |table_block|
        token = placeholder_token(placeholders, "TABLE")
        placeholders[token] = render_table(table_block.split(/\r?\n/).select { |line| line.match?(/\A\|.+\|\z/) })
        token
      end

      text = text.gsub(/```(\w*)\n([\s\S]*?)```/) do
        token = placeholder_token(placeholders, "CODE")
        lang = Regexp.last_match(1)
        code = Regexp.last_match(2)
        lang_attr = lang.present? ? %( data-lang="#{ERB::Util.html_escape(lang)}") : ""
        escaped = ERB::Util.html_escape(code)
        placeholders[token] = %(<div class="code-block-wrap"><button type="button" class="code-copy-btn" data-copy-target="code">#{ERB::Util.html_escape(I18n.t("mcweb.forum.format_post_body.copy"))}</button><pre class="code-block"><code#{lang_attr}>#{escaped}</code></pre></div>)
        token
      end

      # Smilie substitution (admin-defined text codes -> emoji). Runs after code
      # blocks are placeholdered, so codes inside code blocks are untouched.
      # No-op until an admin defines smilies.
      text = apply_smilies(text)

      text = text.gsub(/!\[([^\]]*)\]\(([^)]+)\)/) do
        token = placeholder_token(placeholders, "IMG")
        alt = Regexp.last_match(1)
        url = Regexp.last_match(2)
        next Regexp.last_match(0) unless UrlSafety.safe_image_src?(url)
        placeholders[token] = safe_onebox_image_html(url, "post-image", alt: alt)
        token
      end

      text = text.gsub(/\[video\]\(([^)]+)\)/i) do
        token = placeholder_token(placeholders, "VIDEO")
        url = Regexp.last_match(1)
        embed = video_embed_html(url)
        placeholders[token] = embed if embed
        token
      end

      text = text.gsub(MENTION_PATTERN) do
        username = Regexp.last_match(1)
        token = placeholder_token(placeholders, "MENTION")
        placeholders[token] = %(<a href="/app/forum/users/#{username}" class="mention">@#{username}</a>)
        token
      end

      text = text.gsub(%r{\A(?:/app)?/forum/categories/[\w-]+\s*\z}i) do |path|
        token = placeholder_token(placeholders, "ONEBOX")
        placeholders[token] = category_onebox_html(path) || %(<a href="#{ERB::Util.html_escape(path)}">#{ERB::Util.html_escape(path)}</a>)
        token
      end

      text = text.gsub(%r{\A(?:/app)?/forum/sections/[\w-]+\s*\z}i) do |path|
        token = placeholder_token(placeholders, "ONEBOX")
        placeholders[token] = section_onebox_html(path) || %(<a href="#{ERB::Util.html_escape(path)}">#{ERB::Util.html_escape(path)}</a>)
        token
      end

      text = text.gsub(%r{\A(?:/app)?/forum/tags/[\w-]+\s*\z}i) do |path|
        token = placeholder_token(placeholders, "ONEBOX")
        placeholders[token] = tag_onebox_html(path) || %(<a href="#{ERB::Util.html_escape(path)}">#{ERB::Util.html_escape(path)}</a>)
        token
      end

      text = text.gsub(%r{\A(?:/app)?/forum/users/[\w-]+\s*\z}i) do |path|
        token = placeholder_token(placeholders, "ONEBOX")
        placeholders[token] = user_onebox_html(path) || %(<a href="#{ERB::Util.html_escape(path)}">#{ERB::Util.html_escape(path)}</a>)
        token
      end

      text = text.gsub(%r{\A(?:/app)?/store/products/[\w-]+\s*\z}) do |path|
        token = placeholder_token(placeholders, "ONEBOX")
        placeholders[token] = product_onebox_html(path) || %(<a href="#{ERB::Util.html_escape(path)}">#{ERB::Util.html_escape(path)}</a>)
        token
      end

      text = text.gsub(%r{\A(?:/app)?/forum/topics/[\w-]+\s*\z}) do |path|
        token = placeholder_token(placeholders, "ONEBOX")
        placeholders[token] = topic_onebox_html(path) || %(<a href="#{ERB::Util.html_escape(path)}">#{ERB::Util.html_escape(path)}</a>)
        token
      end

      text = text.gsub(%r{\A(?:/app)?/store/coupons/[\w-]+\s*\z}i) do |path|
        token = placeholder_token(placeholders, "ONEBOX")
        placeholders[token] = coupon_onebox_html(path) || %(<a href="#{ERB::Util.html_escape(path)}">#{ERB::Util.html_escape(path)}</a>)
        token
      end

      text = text.gsub(%r{\A(?:/app)?/store/gift_cards/[\w-]+\s*\z}i) do |path|
        token = placeholder_token(placeholders, "ONEBOX")
        placeholders[token] = gift_card_onebox_html(path) || %(<a href="#{ERB::Util.html_escape(path)}">#{ERB::Util.html_escape(path)}</a>)
        token
      end

      text = text.gsub(/\A(https?:\/\/[^\s]+)\z/) do |url|
        token = placeholder_token(placeholders, "ONEBOX")
        if (embed = video_embed_html(url))
          placeholders[token] = embed
        elsif (product_box = product_onebox_html(url))
          placeholders[token] = product_box
        elsif (topic_box = topic_onebox_html(url))
          placeholders[token] = topic_box
        elsif (user_box = user_onebox_html(url))
          placeholders[token] = user_box
        elsif (coupon_box = coupon_onebox_html(url))
          placeholders[token] = coupon_box
        elsif (gift_card_box = gift_card_onebox_html(url))
          placeholders[token] = gift_card_box
        elsif (section_box = section_onebox_html(url))
          placeholders[token] = section_box
        elsif (tag_box = tag_onebox_html(url))
          placeholders[token] = tag_box
        elsif (category_box = category_onebox_html(url))
          placeholders[token] = category_box
        else
          preview = Community::FetchLinkPreview.call(url: url)
          if preview.success? && preview.value
            p = preview.value
            image_url = p[:image_url].to_s.strip
            img = safe_onebox_image_html(image_url, "onebox-image")
            desc = p[:description].present? ? %(<p class="onebox-desc">#{ERB::Util.html_escape(p[:description].to_s.truncate(200))}</p>) : ""
            placeholders[token] = %(<aside class="onebox"><a href="#{ERB::Util.html_escape(url)}" rel="nofollow noopener" class="onebox-link">#{img}<strong class="onebox-title">#{ERB::Util.html_escape(p[:title].to_s)}</strong>#{desc}</a></aside>)
          else
            placeholders[token] = %(<a href="#{ERB::Util.html_escape(url)}" rel="nofollow noopener">#{ERB::Util.html_escape(url)}</a>)
          end
        end
        token
      end

      html = markdown_to_html(text)
      sanitized = Sanitize.fragment(html, WHITELIST)

      placeholders.each { |token, replacement| sanitized = sanitized.gsub(token, replacement) }
      sanitized = sanitized.gsub(/(?:<li class="task-item">.*?<\/li>\s*)+/) do |block|
        "<ul class=\"task-list\">#{block}</ul>"
      end
      sanitized = apply_footnotes(sanitized, footnote_defs, footnote_used)

      ServiceResult.success(sanitized)
    end

    private

    def extract_footnote_definitions(text)
      defs = {}
      kept = []
      text.each_line do |line|
        if (match = line.match(/\A\[\^([^\]]+)\]:\s*(.+)\s*\z/))
          defs[match[1]] = match[2].strip
        else
          kept << line
        end
      end
      [ kept.join, defs ]
    end

    def apply_footnotes(html, footnote_defs, used_labels)
      labels = used_labels.uniq
      return html if labels.empty?

      items = labels.map do |label|
        safe_label = ERB::Util.html_escape(label)
        %(<li id="fn-#{safe_label}">#{inline_format(footnote_defs[label])} <a href="#fnref-#{safe_label}" class="footnote-back">↩</a></li>)
      end.join
      %(#{html}<div class="post-footnotes"><ol>#{items}</ol></div>)
    end

    def placeholder_token(placeholders, prefix)
      "MCWEB#{prefix}#{placeholders.size}END"
    end

    def apply_smilies(text)
      replacements = Community::Smilie.replacements
      return text if replacements.empty?

      replacements.each do |code, emoji|
        text = text.gsub(code) { emoji }
      end
      text
    end

    # Convert common XenForo BBCode tags to their Markdown equivalents so the
    # existing Markdown pipeline renders them. ([code] is intentionally omitted —
    # fenced ``` blocks already cover it without the inner-tag-escaping problem.)
    def convert_bbcode(text)
      return text unless text.include?("[")

      text = text.gsub(/\[quote(?:=[^\]]*)?\](.*?)\[\/quote\]/mi) do
        Regexp.last_match(1).strip.split(/\r?\n/).map { |line| "> #{line}" }.join("\n").then { |q| "\n#{q}\n" }
      end
      text = text.gsub(/\[b\](.*?)\[\/b\]/mi) { "**#{Regexp.last_match(1)}**" }
      text = text.gsub(/\[i\](.*?)\[\/i\]/mi) { "*#{Regexp.last_match(1)}*" }
      text = text.gsub(/\[u\](.*?)\[\/u\]/mi) { Regexp.last_match(1) }
      text = text.gsub(/\[s\](.*?)\[\/s\]/mi) { "~~#{Regexp.last_match(1)}~~" }
      text = text.gsub(/\[spoiler\](.*?)\[\/spoiler\]/mi) { "||#{Regexp.last_match(1)}||" }
      text = text.gsub(/\[url=([^\]\s]+)\](.*?)\[\/url\]/mi) { "[#{Regexp.last_match(2)}](#{Regexp.last_match(1)})" }
      text = text.gsub(/\[url\](.*?)\[\/url\]/mi) { Regexp.last_match(1) }
      text = text.gsub(/\[img\](.*?)\[\/img\]/mi) { "![](#{Regexp.last_match(1).strip})" }
      apply_custom_bbcodes(text)
    end

    # Admin-defined custom BBCode: [tag]content[/tag] -> the Markdown template
    # with {content} substituted. No-op until any are defined.
    def apply_custom_bbcodes(text)
      definitions = Community::CustomBbcode.definitions
      return text if definitions.empty?

      definitions.each do |tag, replacement|
        pattern = /\[#{Regexp.escape(tag)}\](.*?)\[\/#{Regexp.escape(tag)}\]/mi
        text = text.gsub(pattern) { replacement.gsub("{content}", Regexp.last_match(1)) }
      end
      text
    end

    def safe_onebox_image_html(url, css_class, alt: "")
      src = url.to_s.strip
      return "" unless UrlSafety.safe_image_src?(src)

      alt_attr = alt.present? ? %( alt="#{ERB::Util.html_escape(alt)}") : %( alt="")
      %(<img src="#{ERB::Util.html_escape(src)}"#{alt_attr} class="#{css_class}" loading="lazy" />)
    end

    def video_embed_html(url)
      case url
      when %r{\Ahttps?://(?:www\.)?youtube\.com/watch\?v=([\w-]+)}i,
           %r{\Ahttps?://youtu\.be/([\w-]+)}i
        id = Regexp.last_match(1)
        %(<div class="video-embed"><iframe src="https://www.youtube.com/embed/#{ERB::Util.html_escape(id)}" width="560" height="315" frameborder="0" allowfullscreen loading="lazy" title="YouTube video"></iframe></div>)
      when %r{\Ahttps?://(?:www\.)?vimeo\.com/(\d+)}i
        id = Regexp.last_match(1)
        %(<div class="video-embed"><iframe src="https://player.vimeo.com/video/#{ERB::Util.html_escape(id)}" width="560" height="315" frameborder="0" allowfullscreen loading="lazy" title="Vimeo video"></iframe></div>)
      end
    end

    def product_onebox_html(url)
      result = Community::FetchProductOnebox.call(url: url)
      return nil unless result.success? && result.value

      p = result.value
      img = safe_onebox_image_html(p[:image_url], "onebox-image product-onebox-image")
      summary = p[:summary].present? ? %(<p class="onebox-desc">#{ERB::Util.html_escape(p[:summary].to_s.truncate(120))}</p>) : ""
      %(<aside class="onebox product-onebox"><a href="#{ERB::Util.html_escape(p[:url])}" class="onebox-link">#{img}<strong class="onebox-title">#{ERB::Util.html_escape(p[:name])}</strong>#{summary}<span class="onebox-price">#{ERB::Util.html_escape(p[:price_label])}</span></a></aside>)
    end

    def topic_onebox_html(url)
      result = Community::FetchTopicOnebox.call(url: url)
      return nil unless result.success? && result.value

      t = result.value
      meta = [ t[:author], t[:section_name], I18n.t("mcweb.forum.format_post_body.topic_replies", count: t[:replies_count]) ].compact.join(" · ")
      %(<aside class="onebox topic-onebox"><a href="#{ERB::Util.html_escape(t[:url])}" class="onebox-link"><strong class="onebox-title">#{ERB::Util.html_escape(t[:title])}</strong><p class="onebox-desc">#{ERB::Util.html_escape(meta)}</p></a></aside>)
    end

    def user_onebox_html(url)
      result = Community::FetchUserOnebox.call(url: url)
      return nil unless result.success? && result.value

      u = result.value
      avatar = safe_onebox_image_html(u[:avatar_url], "onebox-image user-onebox-avatar")
      meta = [ u[:trust_name], I18n.t("mcweb.forum.format_post_body.user_posts", count: u[:posts_count]) ].join(" · ")
      %(<aside class="onebox user-onebox"><a href="#{ERB::Util.html_escape(u[:url])}" class="onebox-link">#{avatar}<strong class="onebox-title">#{ERB::Util.html_escape(u[:display_name])}</strong><p class="onebox-desc">@#{ERB::Util.html_escape(u[:username])} · #{ERB::Util.html_escape(meta)}</p></a></aside>)
    end

    def coupon_onebox_html(url)
      result = Community::FetchCouponOnebox.call(url: url)
      return nil unless result.success? && result.value

      c = result.value
      %(<aside class="onebox coupon-onebox"><a href="#{ERB::Util.html_escape(c[:url])}" class="onebox-link"><strong class="onebox-title">#{ERB::Util.html_escape(I18n.t("mcweb.forum.format_post_body.coupon_title", code: c[:code]))}</strong><span class="onebox-price">#{ERB::Util.html_escape(c[:discount_label])}</span></a></aside>)
    end

    def gift_card_onebox_html(url)
      result = Community::FetchGiftCardOnebox.call(url: url)
      return nil unless result.success? && result.value

      g = result.value
      status = g[:redeemable] ? g[:balance_label] : I18n.t("mcweb.forum.format_post_body.unavailable")
      %(<aside class="onebox gift-card-onebox"><a href="#{ERB::Util.html_escape(g[:url])}" class="onebox-link"><strong class="onebox-title">#{ERB::Util.html_escape(I18n.t("mcweb.forum.format_post_body.gift_card_title", code: g[:code]))}</strong><span class="onebox-price">#{ERB::Util.html_escape(I18n.t("mcweb.forum.format_post_body.gift_card_balance", status: status))}</span></a></aside>)
    end

    def section_onebox_html(url)
      result = Community::FetchSectionOnebox.call(url: url)
      return nil unless result.success? && result.value

      s = result.value
      desc = s[:description].present? ? %(<p class="onebox-desc">#{ERB::Util.html_escape(s[:description])}</p>) : ""
      meta = s[:meta].present? ? %(<p class="onebox-desc">#{ERB::Util.html_escape(s[:meta])}</p>) : ""
      %(<aside class="onebox section-onebox"><a href="#{ERB::Util.html_escape(s[:url])}" class="onebox-link"><strong class="onebox-title">#{ERB::Util.html_escape(s[:name])}</strong>#{desc}#{meta}</a></aside>)
    end

    def tag_onebox_html(url)
      result = Community::FetchTagOnebox.call(url: url)
      return nil unless result.success? && result.value

      t = result.value
      desc = t[:description].present? ? %(<p class="onebox-desc">#{ERB::Util.html_escape(t[:description])}</p>) : ""
      %(<aside class="onebox tag-onebox"><a href="#{ERB::Util.html_escape(t[:url])}" class="onebox-link"><strong class="onebox-title">##{ERB::Util.html_escape(t[:name])}</strong>#{desc}<span class="onebox-price">#{ERB::Util.html_escape(I18n.t("mcweb.forum.format_post_body.tag_topics", count: t[:topics_count]))}</span></a></aside>)
    end

    def category_onebox_html(url)
      result = Community::FetchCategoryOnebox.call(url: url)
      return nil unless result.success? && result.value

      c = result.value
      desc = c[:description].present? ? %(<p class="onebox-desc">#{ERB::Util.html_escape(c[:description])}</p>) : ""
      %(<aside class="onebox category-onebox"><a href="#{ERB::Util.html_escape(c[:url])}" class="onebox-link"><strong class="onebox-title">#{ERB::Util.html_escape(c[:name])}</strong>#{desc}<span class="onebox-price">#{ERB::Util.html_escape(I18n.t("mcweb.forum.format_post_body.category_sections", count: c[:section_count]))}</span></a></aside>)
    end

    def markdown_to_html(text)
      lines = text.split(/\r\n|\r|\n/)
      html_lines = []
      in_ul = false
      in_ol = false

      lines.each do |line|
        if (match = line.match(/\A(#+)\s+(.+)\z/))
          html_lines << "</ul>" if in_ul
          in_ul = false
          html_lines << "</ol>" if in_ol
          in_ol = false
          level = [ match[1].length, 6 ].min
          html_lines << "<h#{level}>#{ERB::Util.html_escape(match[2])}</h#{level}>"
        elsif (match = line.match(/\A>\s?(.*)\z/))
          html_lines << "</ul>" if in_ul
          in_ul = false
          html_lines << "</ol>" if in_ol
          in_ol = false
          html_lines << %(<blockquote class="post-quote">#{inline_format(match[1])}</blockquote>)
        elsif line.match(/\A(-{3,}|\*{3,}|_{3,})\s*\z/)
          html_lines << "</ul>" if in_ul
          in_ul = false
          html_lines << "</ol>" if in_ol
          in_ol = false
          html_lines << '<hr class="post-hr" />'
        elsif (match = line.match(/\A[-*]\s+\[([ xX])\]\s+(.+)\z/))
          html_lines << "</ol>" if in_ol
          in_ol = false
          html_lines << "<ul>" unless in_ul
          in_ul = true
          checked = match[1].match?(/[xX]/) ? " checked disabled" : " disabled"
          html_lines << %(<li class="task-item"><input type="checkbox"#{checked} /> #{inline_format(match[2])}</li>)
        elsif (match = line.match(/\A[-*]\s+(.+)\z/))
          html_lines << "</ol>" if in_ol
          in_ol = false
          html_lines << "<ul>" unless in_ul
          in_ul = true
          html_lines << "<li>#{inline_format(match[1])}</li>"
        elsif (match = line.match(/\A\d+\.\s+(.+)\z/))
          html_lines << "</ul>" if in_ul
          in_ul = false
          html_lines << "<ol>" unless in_ol
          in_ol = true
          html_lines << "<li>#{inline_format(match[1])}</li>"
        elsif line.strip.empty?
          html_lines << "</ul>" if in_ul
          in_ul = false
          html_lines << "</ol>" if in_ol
          in_ol = false
          html_lines << "<br>"
        else
          html_lines << "</ul>" if in_ul
          in_ul = false
          html_lines << "</ol>" if in_ol
          in_ol = false
          html_lines << inline_format(line)
        end
      end

      html_lines << "</ul>" if in_ul
      html_lines << "</ol>" if in_ol

      html_lines.join("\n")
    end

    def render_table(rows)
      return "" if rows.empty?

      cells = rows.map { |row| row.split("|").map(&:strip).reject(&:empty?) }
      return "" if cells.empty?

      header = cells.first
      body_rows = cells[1..] || []
      body_rows = body_rows.drop(1) if body_rows.first&.all? { |cell| cell.match?(/\A[-:]+?\z/) }

      thead = "<thead><tr>#{header.map { |cell| "<th>#{inline_format(cell)}</th>" }.join}</tr></thead>"
      tbody = "<tbody>#{body_rows.map { |row| "<tr>#{row.map { |cell| "<td>#{inline_format(cell)}</td>" }.join}</tr>" }.join}</tbody>"
      %(<table class="post-table">#{thead}#{tbody}</table>)
    end

    def inline_format(text)
      escaped = ERB::Util.html_escape(text)
      escaped = escaped.gsub(/\*\*(.+?)\*\*/, '<strong>\1</strong>')
      escaped = escaped.gsub(/\*(.+?)\*/, '<em>\1</em>')
      escaped = escaped.gsub(/~~(.+?)~~/, '<del>\1</del>')
      escaped = escaped.gsub(/`([^`]+)`/, '<code>\1</code>')
      escaped.gsub(/\[([^\]]+)\]\((https?:\/\/[^)]+)\)/) do
        label = Regexp.last_match(1)
        url = Regexp.last_match(2)
        if (product_box = product_onebox_html(url))
          product_box
        elsif (topic_box = topic_onebox_html(url))
          topic_box
        elsif (user_box = user_onebox_html(url))
          user_box
        elsif (coupon_box = coupon_onebox_html(url))
          coupon_box
        elsif (gift_card_box = gift_card_onebox_html(url))
          gift_card_box
        elsif (section_box = section_onebox_html(url))
          section_box
        elsif (tag_box = tag_onebox_html(url))
          tag_box
        elsif (category_box = category_onebox_html(url))
          category_box
        else
          %(<a href="#{ERB::Util.html_escape(url)}" rel="nofollow noopener">#{ERB::Util.html_escape(label)}</a>)
        end
      end
    end
  end
end
