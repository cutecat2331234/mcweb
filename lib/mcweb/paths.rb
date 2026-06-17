# frozen_string_literal: true

module Mcweb
  module Paths
    APP_PREFIX = "/app"
    LEGACY_APP_SCOPES = %w[/forum /store /identity /minecraft /payments].freeze

    module_function

    def helpers
      Rails.application.routes.url_helpers
    end

    def normalize(path)
      return path if path.blank?
      return path if path.match?(%r{\Ahttps?://}i)

      bare = path.start_with?("/") ? path : "/#{path}"
      return bare if bare == APP_PREFIX || bare.start_with?("#{APP_PREFIX}/")

      LEGACY_APP_SCOPES.each do |scope|
        return "#{APP_PREFIX}#{bare}" if bare == scope || bare.start_with?("#{scope}/")
      end

      bare
    end
  end
end
