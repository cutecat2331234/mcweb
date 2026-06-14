# frozen_string_literal: true

module Website
  class BlockSanitizer < ApplicationService
    WHITELIST = {
      elements: %w[
        p br strong em u s del h1 h2 h3 h4 h5 h6
        ul ol li blockquote pre code a img span div
      ],
      attributes: {
        "a" => %w[href title target rel],
        "img" => %w[src alt title width height],
        "span" => %w[class],
        "div" => %w[class]
      },
      protocols: {
        "a" => { "href" => %w[http https mailto] },
        "img" => { "src" => %w[http https] }
      }
    }.freeze

    def initialize(html:)
      @html = html
    end

    def call
      raw = @html.is_a?(CustomSafeHtml) ? @html.to_s : @html.to_s
      sanitized = Sanitize.fragment(raw, WHITELIST)
      ServiceResult.success(CustomSafeHtml.wrap(sanitized))
    end
  end
end
