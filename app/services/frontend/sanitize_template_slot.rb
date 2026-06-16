# frozen_string_literal: true

module Frontend
  class SanitizeTemplateSlot < ApplicationService
    WHITELIST = {
      elements: %w[
        p br strong em u s del h1 h2 h3 h4 h5 h6
        ul ol li blockquote pre code a img span div nav header footer section
      ],
      attributes: {
        "a" => %w[href title target rel class],
        "img" => %w[src alt title width height class],
        "span" => %w[class],
        "div" => %w[class],
        "nav" => %w[class],
        "header" => %w[class],
        "footer" => %w[class],
        "section" => %w[class]
      },
      protocols: {
        "a" => { "href" => %w[http https mailto /] },
        "img" => { "src" => %w[http https /] }
      }
    }.freeze

    def initialize(html)
      @html = html.to_s
    end

    def call
      return ServiceResult.success(nil) if @html.blank?

      ServiceResult.success(Sanitize.fragment(@html, WHITELIST))
    end
  end
end
