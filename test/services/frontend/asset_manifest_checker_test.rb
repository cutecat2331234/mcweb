# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class Frontend::AssetManifestCheckerTest < ActiveSupport::TestCase
  ApplicationDescriptor = Data.define(:runtime_kind, :entrypoint)
  Registry = Data.define(:applications)

  def with_build(application_registry: registry)
    Dir.mktmpdir("mcweb-vite-manifest") do |directory|
      root = Pathname(directory)
      assets = root.join("assets")
      assets.mkpath
      entrypoints = vite_entrypoints(application_registry)
      document = {}

      entrypoints.each_with_index do |entrypoint, index|
        filename = entrypoint_asset_filename(entrypoint, index)
        assets.join(File.basename(filename)).write("entry")
        document[entrypoint] = { "file" => filename }
      end

      stylesheet = "assets/shared-IjKl9012.css"
      assets.join(File.basename(stylesheet)).write("style")
      document.fetch(entrypoints.first)["css"] = [ stylesheet ]
      document.fetch(entrypoints.last)["imports"] = [ entrypoints.first ] if entrypoints.many?

      manifest = root.join("manifest.json")
      manifest.write(JSON.generate(document))
      yield root, manifest, entrypoints
    end
  end

  test "derives the complete Vite entrypoint set from the application registry" do
    expected_entrypoints = %w[
      entrypoints/account.ts
      entrypoints/admin.ts
      entrypoints/forum.ts
      entrypoints/staff.ts
      entrypoints/store.ts
      entrypoints/website-document.ts
      entrypoints/website-preview.ts
    ].sort

    with_build do |root, manifest, entrypoints|
      result = checker(root:, manifest:).call

      assert_equal expected_entrypoints, entrypoints
      assert_not_includes entrypoints, "entrypoints/inertia.ts"
      assert_equal "ok", result[:status]
      assert_equal "manifest_and_files", result[:probe]
      assert_equal expected_entrypoints.length, result[:entrypoints]
      assert_equal expected_entrypoints.length + 1, result[:assets]
    end
  end

  test "requires every registered Vite application entrypoint" do
    with_build do |root, manifest, entrypoints|
      document = JSON.parse(manifest.read)
      document.delete(entrypoints.fetch(2))
      manifest.write(JSON.generate(document))

      result = checker(root:, manifest:).call

      assert_equal "frontend_manifest_entry_missing", result[:error_code]
    end
  end

  test "does not require an Astro document renderer in the Vite manifest" do
    application_registry = Registry.new([
      ApplicationDescriptor.new("inertia", "forum"),
      ApplicationDescriptor.new("astro_document", "website")
    ])

    with_build(application_registry:) do |root, manifest, entrypoints|
      result = checker(root:, manifest:, application_registry:).call

      assert_equal [ "entrypoints/forum.ts" ], entrypoints
      assert_equal "ok", result[:status]
      assert_equal 1, result[:entrypoints]
    end
  end

  test "rejects missing files and dependency keys" do
    with_build do |root, manifest, entrypoints|
      document = JSON.parse(manifest.read)
      missing_file = document.fetch(entrypoints.fetch(1)).fetch("file")
      root.join(missing_file).delete

      result = checker(root:, manifest:).call
      assert_equal "frontend_asset_missing", result[:error_code]

      document.fetch(entrypoints.last)["imports"] = [ "entrypoints/missing.ts" ]
      manifest.write(JSON.generate(document))
      result = checker(root:, manifest:).call
      assert_equal "frontend_manifest_reference_missing", result[:error_code]
    end
  end

  test "rejects unhashed or escaping asset paths" do
    with_build do |root, manifest, entrypoints|
      document = JSON.parse(manifest.read)
      first_entrypoint = entrypoints.first
      document.fetch(first_entrypoint)["file"] = "assets/account.js"
      root.join("assets/account.js").write("entry")
      manifest.write(JSON.generate(document))

      result = checker(root:, manifest:).call
      assert_equal "frontend_asset_unhashed", result[:error_code]

      document.fetch(first_entrypoint)["file"] = "../outside-AbCd1234.js"
      manifest.write(JSON.generate(document))
      result = checker(root:, manifest:).call
      assert_equal "frontend_asset_path_invalid", result[:error_code]
    end
  end

  private

  def registry
    @registry ||= Frontend::ApplicationRegistry.new(root: Rails.root)
  end

  def checker(root:, manifest:, application_registry: registry)
    Frontend::AssetManifestChecker.new(
      manifest_path: manifest,
      output_directory: root,
      application_registry: application_registry
    )
  end

  def vite_entrypoints(application_registry)
    application_registry.applications
      .select do |application|
        Frontend::AssetManifestChecker::VITE_RUNTIME_KINDS.include?(application.runtime_kind)
      end
      .map { |application| "entrypoints/#{application.entrypoint}.ts" }
      .uniq
      .sort
  end

  def entrypoint_asset_filename(entrypoint, index)
    stem = File.basename(entrypoint, ".ts")
    "assets/#{stem}-#{format('%08d', index + 1)}.js"
  end
end
