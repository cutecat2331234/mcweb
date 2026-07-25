# frozen_string_literal: true

module Community
  class ExtractEmailReplyBody
    MAX_BODY_LENGTH = 20_000
    QUOTE_BOUNDARIES = [
      /\AOn .+wrote:\s*\z/i,
      /\A在.+写道[：:]\s*\z/,
      /\A-{2,}\s*Original Message\s*-{2,}\s*\z/i,
      /\A-{2,}\s*原始邮件\s*-{2,}\s*\z/,
      /\AFrom:\s+.+\z/i,
      /\A发件人[：:]\s*.+\z/
    ].freeze
    SIGNATURE_BOUNDARIES = [
      /\A--\s*\z/,
      /\ASent from my .+\z/i,
      /\A从我的 .+ 发送\z/
    ].freeze

    def self.call(mail)
      new(mail).call
    end

    def initialize(mail)
      @mail = mail
    end

    def call
      lines = decoded_text
        .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
        .gsub(/\r\n?/, "\n")
        .lines(chomp: true)

      kept = []
      lines.each do |line|
        stripped = line.strip
        break if boundary?(stripped)
        next if stripped.start_with?(">")

        kept << line.rstrip
      end

      body = kept.join("\n")
        .gsub(/\n{3,}/, "\n\n")
        .strip

      body.first(MAX_BODY_LENGTH)
    end

    private

    def decoded_text
      part = @mail.text_part
      return part.decoded.to_s if part

      if @mail.html_part
        return html_to_text(@mail.html_part.decoded.to_s)
      end

      body = @mail.body.decoded.to_s
      @mail.mime_type == "text/html" ? html_to_text(body) : body
    end

    def html_to_text(html)
      fragment = Nokogiri::HTML.fragment(html)
      fragment.css(
        "blockquote, .gmail_quote, .yahoo_quoted, .protonmail_quote, #divRplyFwdMsg"
      ).remove
      fragment.css("br").each { |node| node.replace("\n") }
      fragment.css("p,div,li,h1,h2,h3,h4,h5,h6").each do |node|
        node.add_next_sibling(Nokogiri::XML::Text.new("\n", fragment.document))
      end
      fragment.text
    end

    def boundary?(line)
      QUOTE_BOUNDARIES.any? { |pattern| line.match?(pattern) } ||
        SIGNATURE_BOUNDARIES.any? { |pattern| line.match?(pattern) }
    end
  end
end
