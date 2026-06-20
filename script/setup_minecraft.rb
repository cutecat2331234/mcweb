#!/usr/bin/env ruby
# frozen_string_literal: true

# Helper for co-located Minecraft server + McWeb installs.
#
# DEPRECATED: Prefer `bin/setup-local-config` for config/local.yml bootstrap.
# This script remains for server operators who already rely on it.
#
# McWeb does NOT load `local.env` — instance settings belong in config/local.yml.
# Production systemd units may use /etc/mcweb/mcweb.env for REDIS_URL and similar
# process environment variables only; database credentials go in local.yml.

require "pathname"

APP_ROOT = Pathname.new(__dir__).join("..").expand_path
$LOAD_PATH.unshift(APP_ROOT.join("lib").to_s)

require "mcweb/local_config"
require "mcweb/resolve_local_config"

warn "[setup_minecraft] DEPRECATED: use bin/setup-local-config instead."

server_root = ARGV[0] || ENV["MCWEB_SERVER_ROOT"]
if server_root.to_s.strip.empty?
  warn "Usage: script/setup_minecraft.rb [server_root]"
  warn "  server_root defaults to MCWEB_SERVER_ROOT or auto-detected ../server"
  exit 1
end

ENV["MCWEB_SERVER_ROOT"] = File.expand_path(server_root)

result = Mcweb::ResolveLocalConfig.call(server_root: Pathname(ENV["MCWEB_SERVER_ROOT"]))

puts "McWeb local config: #{result.path} (#{result.source})"
puts "local.env is not read by Rails — configure database/secrets in config/local.yml."
puts "Open /setup after starting the app to complete the wizard."
