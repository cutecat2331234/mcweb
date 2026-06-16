# frozen_string_literal: true

module Frontend
  class BuildTemplateAssetUrl
    def self.call(template_key:, path:)
      new(template_key: template_key, path: path).to_s
    end

    def initialize(template_key:, path:)
      @template_key = template_key.to_s
      @path = path.to_s.delete_prefix("/")
    end

    def to_s
      Rails.application.routes.url_helpers.frontend_theme_asset_path(
        template_key: @template_key,
        path: @path
      )
    end
  end
end
