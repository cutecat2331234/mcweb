# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/marketplace"
require "tmpdir"

class Mcweb::Plugins::Marketplace::FileHealthTest < ActiveSupport::TestCase
  setup do
    @temporary = Pathname(Dir.mktmpdir("mcweb-plugin-health"))
    @plugin_root = @temporary.join("plugin")
    @plugin_root.join("lib").mkpath
    @plugin_root.join("mcweb_plugin.yml").write("id: acme/demo\n")
    @plugin_root.join("lib/demo.rb").write("DEMO = true\n")
  end

  teardown do
    FileUtils.remove_entry(@temporary) if @temporary&.exist?
  end

  test "builds a deterministic manifest and reports a healthy tree" do
    manifest = Mcweb::Plugins::Marketplace::FileHealth.manifest(@plugin_root)

    assert_equal "sha256", manifest.fetch("algorithm")
    assert_equal %w[lib/demo.rb mcweb_plugin.yml], manifest.fetch("files").pluck("path")

    result = Mcweb::Plugins::Marketplace::FileHealth.check(
      directory: @plugin_root,
      expected: manifest
    )

    assert result.healthy?
    assert_equal 2, result.expected_count
    assert_equal 2, result.actual_count
    assert_empty result.missing
    assert_empty result.modified
    assert_empty result.unknown
  end

  test "reports missing modified and unknown files without leaking their contents" do
    manifest = Mcweb::Plugins::Marketplace::FileHealth.manifest(@plugin_root)
    @plugin_root.join("lib/demo.rb").write("DEMO = false\n")
    @plugin_root.join("mcweb_plugin.yml").delete
    @plugin_root.join("extra.txt").write("access_token=never-return")

    result = Mcweb::Plugins::Marketplace::FileHealth.check(
      directory: @plugin_root,
      expected: manifest
    )

    assert_equal "changed", result.status
    assert_equal [ "mcweb_plugin.yml" ], result.missing
    assert_equal [ "lib/demo.rb" ], result.modified
    assert_equal [ "extra.txt" ], result.unknown
    refute_includes result.to_h.to_json, "never-return"
  end

  test "returns a stable unavailable result for an invalid baseline" do
    result = Mcweb::Plugins::Marketplace::FileHealth.check(
      directory: @plugin_root,
      expected: { "algorithm" => "md5", "files" => [] }
    )

    assert_equal "unavailable", result.status
    assert_empty result.missing
    assert_empty result.modified
    assert_empty result.unknown
  end
end
