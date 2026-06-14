# frozen_string_literal: true

InertiaRails.configure do |config|
  config.version = ViteRuby.digest
  config.ssr_enabled = false
  config.always_include_errors_hash = true
  # Inertia.js 3.x reads initial page from a JSON script tag, not a div attribute.
  config.use_script_element_for_initial_page = true
end
