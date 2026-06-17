# frozen_string_literal: true

module Mcweb
  module Paths
    APP_PREFIX = "/app"

    module_function

    def helpers
      Rails.application.routes.url_helpers
    end
  end
end
