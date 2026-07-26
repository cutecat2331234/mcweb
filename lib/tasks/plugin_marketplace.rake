# frozen_string_literal: true

require "json"
require "mcweb/plugins/marketplace"

namespace :plugins do
  namespace :marketplace do
    desc "Install or upgrade a reviewed plugin ZIP (PACKAGE, SOURCE, SHA256; optional ID, ALLOW_DOWNGRADE=1)"
    task install: :environment do
      result = Mcweb::Plugins::Marketplace.manager.install(
        package_path: ENV.fetch("PACKAGE"),
        source: ENV.fetch("SOURCE"),
        expected_sha256: ENV.fetch("SHA256"),
        expected_id: ENV["ID"],
        allow_downgrade: ENV["ALLOW_DOWNGRADE"] == "1"
      )
      puts JSON.pretty_generate(result.to_h)
    end

    desc "Disable an installed plugin without deleting its files (ID)"
    task disable: :environment do
      result = Mcweb::Plugins::Marketplace.manager.disable(plugin_id: ENV.fetch("ID"))
      puts JSON.pretty_generate(result.to_h)
    end

    desc "Enable a disabled plugin (ID)"
    task enable: :environment do
      result = Mcweb::Plugins::Marketplace.manager.enable(plugin_id: ENV.fetch("ID"))
      puts JSON.pretty_generate(result.to_h)
    end

    desc "Uninstall the exact reviewed plugin into recoverable quarantine (ID, VERSION, SHA256)"
    task uninstall: :environment do
      result = Mcweb::Plugins::Marketplace.manager.uninstall(
        plugin_id: ENV.fetch("ID"),
        expected_version: ENV.fetch("VERSION"),
        expected_sha256: ENV.fetch("SHA256")
      )
      puts JSON.pretty_generate(result.to_h)
    end

    desc "Show installed plugin state, validation errors, and recent operations (optional ID, LIMIT)"
    task status: :environment do
      result = Mcweb::Plugins::Marketplace.manager.status(
        plugin_id: ENV["ID"],
        recent_operations: ENV.fetch("LIMIT", "100").to_i
      )
      puts JSON.pretty_generate(result)
    end
  end
end
