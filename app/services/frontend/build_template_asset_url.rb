# frozen_string_literal: true

module Frontend
  class BuildTemplateAssetUrl
    def initialize(template_key:, path:, cache_version: nil)
      @template_key = template_key.to_s
      @path = path.to_s.delete_prefix("/")
      @cache_version = cache_version.presence
    end

    def self.call(template_key:, path:, cache_version: nil)
      new(template_key: template_key, path: path, cache_version: cache_version).to_s
    end

    def to_s
      base = Rails.application.routes.url_helpers.frontend_theme_asset_path(
        template_key: @template_key,
        path: @path
      )
      return base if @cache_version.blank?

      "#{base}?v=#{@cache_version}"
    end
  end
end
