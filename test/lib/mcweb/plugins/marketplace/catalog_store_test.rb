# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/marketplace/catalog_store"
require "tmpdir"

class Mcweb::Plugins::Marketplace::CatalogStoreTest < ActiveSupport::TestCase
  setup do
    @temporary = Pathname(Dir.mktmpdir("mcweb-plugin-catalog"))
    @plugin_root = @temporary.join("acme/demo")
    @plugin_root.mkpath
    write_plugin(version: "1.0.0")
    @manifest = Mcweb::Plugins::Manifest.load_file(
      @plugin_root.join("mcweb_plugin.yml")
    )
    @file_manifest =
      Mcweb::Plugins::Marketplace::FileHealth.manifest(@plugin_root)
    @store = Mcweb::Plugins::Marketplace::CatalogStore.new
  end

  teardown do
    FileUtils.remove_entry(@temporary) if @temporary&.exist?
  end

  test "persists safe release contribution and file snapshots idempotently" do
    first = synchronize
    second = synchronize

    assert first.created
    refute second.created
    assert_equal first.release_id, second.release_id
    assert_equal 1, PluginRelease.count

    release = PluginRelease.includes(:contributions, :files).sole
    assert_equal "active", release.state
    assert_equal "healthy", release.health
    assert_equal "receipt", release.package_digest_source
    assert_equal "Demo", release.manifest_descriptor.fetch("name")
    refute release.manifest_descriptor.key?("source_path")
    refute release.manifest_descriptor.key?("homepage")
    refute_includes release.to_json, @temporary.to_s
    refute_includes release.to_json, "access_token"

    contribution = release.contributions.sole
    assert_equal "acme.demo.slot.summary", contribution.contribution_id
    assert_equal "ui_slot", contribution.contribution_type
    assert_match(/\A[0-9a-f]{64}\z/, contribution.descriptor_sha256)
    assert_match(/\A[0-9a-f]{64}\z/, contribution.schema_sha256)
    refute contribution.descriptor.key?("source")
    refute contribution.descriptor.key?("schema")

    assert release.files.all? { |file| file.health == "healthy" }
    assert release.files.all? { |file| !Pathname(file.path).absolute? }
  end

  test "records modified and unexpected files without replacing the baseline" do
    synchronize
    @plugin_root.join("plugin.rb").write("PLUGIN = :changed\n")
    @plugin_root.join("unexpected.txt").write("operator note\n")

    result = synchronize
    release = PluginRelease.includes(:files).find(result.release_id)

    assert_equal "changed", release.health
    modified = release.files.find { |file| file.path == "plugin.rb" }
    unexpected = release.files.find { |file| file.path == "unexpected.txt" }
    assert_equal "modified", modified.health
    assert_not_equal modified.sha256, modified.observed_sha256
    assert_equal "unknown", unexpected.health
    refute_predicate unexpected, :expected?
  end

  test "backfill derives a digest and transitions the current release state" do
    result = @store.synchronize!(
      plugin_id: "acme/demo",
      state: "active",
      manifest: @manifest,
      directory: @plugin_root,
      diagnostics: [
        { code: "receipt_missing", severity: "warning" }
      ]
    )
    release = PluginRelease.find(result.release_id)

    assert_equal "derived", release.package_digest_source
    assert_equal "untracked", release.health
    assert_equal [ "receipt_missing", "package_digest_derived" ],
                 release.diagnostics.pluck("code")

    @store.synchronize!(
      plugin_id: "acme/demo",
      state: "disabled",
      manifest: @manifest,
      package_sha256: release.package_sha256,
      expected_file_manifest: @file_manifest,
      directory: @plugin_root
    )
    assert_equal "disabled", release.reload.state
    assert_equal "disabled",
                 PluginInstallation.find_by!(plugin_id: "acme/demo").current_state
  end

  private

  def synchronize
    @store.synchronize!(
      plugin_id: "acme/demo",
      state: "active",
      manifest: @manifest,
      package_sha256: "a" * 64,
      expected_file_manifest: @file_manifest,
      directory: @plugin_root,
      operation_id: "operation-safe"
    )
  end

  def write_plugin(version:)
    manifest = {
      "id" => "acme/demo",
      "name" => "Demo",
      "version" => version,
      "api_version" => "1",
      "homepage" => "https://example.test/?access_token=never-store",
      "capabilities" => [ "site.pages.read" ],
      "contributions" => {
        "catalog" => "contributions.yml"
      },
      "entrypoint" => "plugin.rb"
    }
    contributions = {
      "schema_version" => "1",
      "contributions" => [
        {
          "type" => "ui_slot",
          "id" => "acme.demo.slot.summary",
          "payload" => {
            "slot" => "dashboard.cards",
            "kind" => "card",
            "title_phrase" => "acme.demo.summary.title",
            "schema" => { "kind" => "summary" }
          }
        }
      ]
    }
    @plugin_root.join("mcweb_plugin.yml").write(manifest.to_yaml)
    @plugin_root.join("contributions.yml").write(contributions.to_yaml)
    @plugin_root.join("plugin.rb").write("PLUGIN = true\n")
  end
end
