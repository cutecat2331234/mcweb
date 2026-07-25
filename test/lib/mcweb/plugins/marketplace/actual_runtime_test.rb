# frozen_string_literal: true

require "test_helper"
require "digest"
require "mcweb/plugins/marketplace"
require "tmpdir"
require "zip"

class Mcweb::Plugins::Marketplace::ActualRuntimeTest < ActiveSupport::TestCase
  parallelize(workers: 1)

  setup do
    Mcweb::Plugins.reset!
    @temporary = Pathname(Dir.mktmpdir("mcweb-marketplace-runtime"))
    @root = @temporary.join("plugins")
    @manager = Mcweb::Plugins::Marketplace::Manager.new(
      root: @root,
      state_root: @temporary.join("state")
    )
  end

  teardown do
    Mcweb::Plugins.reset!
    FileUtils.remove_entry(@temporary) if @temporary&.exist?
  end

  test "manager activates and disables a package through the real plugin loader" do
    package = @temporary.join("runtime.zip")
    Zip::File.open(package, create: true) do |archive|
      archive.get_output_stream("mcweb_plugin.yml") do |stream|
        stream.write(
          {
            "id" => "runtime/example",
            "name" => "Runtime example",
            "version" => "1.0.0",
            "api_version" => "1",
            "entrypoint" => "plugin.rb"
          }.to_yaml
        )
      end
      archive.get_output_stream("plugin.rb") do |stream|
        stream.write("Mcweb::Plugins.register\n")
      end
    end

    installed = @manager.install(
      package_path: package,
      source: "file:///reviewed/runtime.zip",
      expected_sha256: Digest::SHA256.file(package).hexdigest
    )

    assert_equal "active", installed.status
    assert_equal [ "runtime/example" ], Mcweb::Plugins.list.pluck(:id)
    assert_equal "active", Mcweb::Plugins.list.sole.fetch(:status)

    @manager.disable(plugin_id: "runtime/example")
    assert_empty Mcweb::Plugins.list
  end
end
