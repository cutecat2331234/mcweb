# frozen_string_literal: true

require "mcweb/plugins/loader"
require "mcweb/plugins/generation_coordinator"

# Deployment plugins are trusted Ruby code loaded from plugins/**/mcweb_plugin.yml.
# to_prepare runs for every development request. The registry performs a cheap,
# bounded source signature check so unchanged requests do not reset event
# subscriptions or re-evaluate trusted plugin entrypoints.
plugin_root = Mcweb::Plugins.default_root.expand_path
if Rails.env.development? && plugin_root.directory?
  Rails.application.config.watchable_dirs[plugin_root.to_s] ||= %w[rb yml yaml]
end

Rails.application.config.to_prepare do
  Mcweb::Plugins.reload_if_changed!
end
