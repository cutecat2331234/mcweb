# frozen_string_literal: true

require_relative "../lib/mcweb/developer_mode"

settings = Mcweb::DeveloperMode.settings
if settings.enabled?
  ViteRuby.env["MCWEB_DEVELOPER_VITE"] = "1"

  {
    "MCWEB_DEVELOPER_VITE_MINIFICATION" => :asset_minification,
    "MCWEB_DEVELOPER_VITE_SOURCE_MAPS" => :source_maps
  }.each do |environment_key, runtime_key|
    value = settings.runtime.fetch(runtime_key)
    ViteRuby.env[environment_key] = value.to_s unless value == :inherit
  end
end
