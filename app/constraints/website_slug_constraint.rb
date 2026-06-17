# frozen_string_literal: true

class WebsiteSlugConstraint
  RESERVED = %w[
    app admin setup forum store identity minecraft payments health jobs up blog api rails
    theme-assets health live ready
  ].freeze

  SLUG_PATTERN = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

  def self.matches?(request)
    slug = request.path_parameters[:slug].to_s
    slug.match?(SLUG_PATTERN) && !RESERVED.include?(slug)
  end
end
