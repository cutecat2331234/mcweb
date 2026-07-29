# frozen_string_literal: true

require "mcweb/plugins/devtools"

namespace :plugin do
  def run_plugin_devtool(command, *arguments)
    argv = [ command, *arguments.compact ]
    argv << "--json" if ENV["JSON"] == "1"
    status = Mcweb::Plugins::Devtools::Command.run(argv)
    exit(status) unless status.zero?
  end

  desc "Create a plugin scaffold (ID, optional ROOT, NAME, AUTHOR, JSON=1)"
  task create: :environment do
    arguments = [ ENV.fetch("ID") ]
    arguments.concat([ "--root", ENV["ROOT"] ]) if ENV["ROOT"].present?
    arguments.concat([ "--name", ENV["NAME"] ]) if ENV["NAME"].present?
    arguments.concat([ "--author", ENV["AUTHOR"] ]) if ENV["AUTHOR"].present?
    run_plugin_devtool("create", *arguments)
  end

  desc "Validate a plugin (PATH, optional PLUGINS_ROOT, TARGET_API, JSON=1)"
  task validate: :environment do
    arguments = [ ENV.fetch("PATH") ]
    arguments.concat([ "--plugins-root", ENV["PLUGINS_ROOT"] ]) if ENV["PLUGINS_ROOT"].present?
    arguments.concat([ "--target-api", ENV["TARGET_API"] ]) if ENV["TARGET_API"].present?
    run_plugin_devtool("validate", *arguments)
  end

  desc "Run plugin contract and host tests (PATH, optional SKIP_PLUGIN_TESTS=1, JSON=1)"
  task test: :environment do
    arguments = [ ENV.fetch("PATH") ]
    arguments << "--skip-plugin-tests" if ENV["SKIP_PLUGIN_TESTS"] == "1"
    run_plugin_devtool("test", *arguments)
  end

  desc "Build a reproducible plugin ZIP (PATH, optional OUTPUT, WITHOUT_TESTS=1, JSON=1)"
  task build: :environment do
    arguments = [ ENV.fetch("PATH") ]
    arguments.concat([ "--output", ENV["OUTPUT"] ]) if ENV["OUTPUT"].present?
    arguments << "--without-tests" if ENV["WITHOUT_TESTS"] == "1"
    run_plugin_devtool("build", *arguments)
  end

  desc "Create release notes and artifacts (PATH, optional OUTPUT, WITHOUT_TESTS=1, JSON=1)"
  task release: :environment do
    arguments = [ ENV.fetch("PATH") ]
    arguments.concat([ "--output", ENV["OUTPUT"] ]) if ENV["OUTPUT"].present?
    arguments << "--without-tests" if ENV["WITHOUT_TESTS"] == "1"
    run_plugin_devtool("release", *arguments)
  end

  desc "Check source or installed plugin health (TARGET, optional INSTALLED=1, JSON=1)"
  task health: :environment do
    arguments = [ ENV.fetch("TARGET") ]
    arguments << "--installed" if ENV["INSTALLED"] == "1"
    run_plugin_devtool("health", *arguments)
  end
end
