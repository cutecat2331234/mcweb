# frozen_string_literal: true

InertiaRails.configure do |config|
  config.version = ViteRuby.digest
  config.ssr_enabled = false
  config.always_include_errors_hash = true
end
