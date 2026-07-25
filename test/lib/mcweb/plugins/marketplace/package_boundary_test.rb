# frozen_string_literal: true

require "test_helper"
require "digest"
require "mcweb/plugins/marketplace"
require "tmpdir"
require "zip"

class Mcweb::Plugins::Marketplace::PackageBoundaryTest < ActiveSupport::TestCase
  setup do
    @temporary = Pathname(Dir.mktmpdir("mcweb-marketplace-package"))
  end

  teardown do
    FileUtils.remove_entry(@temporary) if @temporary&.exist?
  end

  test "source accepts file and HTTPS provenance but never persists query credentials" do
    source = Mcweb::Plugins::Marketplace::PackageSource.new(
      "https://packages.example.test/acme/demo.zip?token=secret#download"
    )

    assert_equal "https", source.scheme
    assert_equal "packages.example.test", source.host
    assert_equal "https://packages.example.test/acme/demo.zip", source.canonical_url
    refute_includes source.to_h.to_json, "secret"

    assert_raises(Mcweb::Plugins::Marketplace::SourceError) do
      Mcweb::Plugins::Marketplace::PackageSource.new("http://packages.example.test/demo.zip")
    end
    assert_raises(Mcweb::Plugins::Marketplace::SourceError) do
      Mcweb::Plugins::Marketplace::PackageSource.new("https://user:password@packages.example.test/demo.zip")
    end
  end

  test "archive verifies digest and extracts normalized package files" do
    package = write_zip(
      "valid.zip",
      "mcweb_plugin.yml" => manifest_yaml,
      "plugin.rb" => "Mcweb::Plugins.register\n",
      "assets/icon.txt" => "icon"
    )
    destination = @temporary.join("staged")
    archive = archive_for(package)

    archive.extract_to(destination)

    assert_equal "icon", destination.join("assets/icon.txt").read
    assert_equal Digest::SHA256.file(package).hexdigest, archive.sha256
    assert_equal 0o644, destination.join("plugin.rb").stat.mode & 0o777
  end

  test "archive rejects traversal Git metadata and case-insensitive collisions" do
    invalid_packages = [
      write_zip(
        "traversal.zip",
        "mcweb_plugin.yml" => manifest_yaml,
        "plugin.rb" => "safe",
        "../outside.rb" => "escape"
      ),
      write_zip(
        "git.zip",
        "mcweb_plugin.yml" => manifest_yaml,
        "plugin.rb" => "safe",
        ".git/config" => "url=https://token@example.test/repository"
      ),
      write_zip(
        "collision.zip",
        "mcweb_plugin.yml" => manifest_yaml,
        "plugin.rb" => "one",
        "PLUGIN.RB" => "two"
      ),
      write_zip(
        "ntfs-stream.zip",
        "mcweb_plugin.yml" => manifest_yaml,
        "plugin.rb" => "safe",
        "assets/config.txt:secret" => "hidden"
      )
    ]

    invalid_packages.each_with_index do |package, index|
      destination = @temporary.join("invalid-#{index}")
      assert_raises(Mcweb::Plugins::Marketplace::PackageError) do
        archive_for(package).extract_to(destination)
      end
      refute destination.exist?
    end
    refute @temporary.join("outside.rb").exist?
  end

  test "archive requires one manifest at package root" do
    nested = write_zip(
      "nested.zip",
      "nested/mcweb_plugin.yml" => manifest_yaml,
      "nested/plugin.rb" => "safe"
    )

    error = assert_raises(Mcweb::Plugins::Marketplace::PackageError) do
      archive_for(nested).extract_to(@temporary.join("nested-stage"))
    end
    assert_includes error.message, "root mcweb_plugin.yml"
  end

  test "metadata validates identity and host runtime requirements" do
    path = @temporary.join("mcweb_package.yml")
    path.write(
      {
        "schema_version" => "1",
        "plugin" => { "id" => "acme/demo", "version" => "1.0.0" },
        "compatibility" => {
          "plugin_api" => "~> 1.0",
          "ruby" => ">= 4.0",
          "rails" => ">= 8.1"
        }
      }.to_yaml
    )
    metadata = Mcweb::Plugins::Marketplace::PackageMetadata.load_file(path)
    manifest = Mcweb::Plugins::Manifest.from_hash(
      {
        id: "acme/demo",
        name: "Demo",
        version: "1.0.0",
        api_version: "1"
      }
    )

    assert metadata.validate!(manifest:, ruby_version: "4.0.6", rails_version: "8.1.2")
    assert_raises(Mcweb::Plugins::Marketplace::CompatibilityError) do
      metadata.validate!(manifest:, ruby_version: "3.4.0", rails_version: "8.1.2")
    end
  end

  test "metadata rejects duplicate mapping keys" do
    path = @temporary.join("mcweb_package.yml")
    path.write(<<~YAML)
      schema_version: "1"
      plugin:
        id: acme/demo
        id: other/demo
        version: 1.0.0
    YAML

    error = assert_raises(Mcweb::Plugins::Marketplace::PackageError) do
      Mcweb::Plugins::Marketplace::PackageMetadata.load_file(path)
    end
    assert_includes error.message, "duplicate"
  end

  test "archive rejects a digest mismatch before creating staging files" do
    package = write_zip(
      "digest.zip",
      "mcweb_plugin.yml" => manifest_yaml,
      "plugin.rb" => "safe"
    )
    destination = @temporary.join("digest-stage")
    archive = Mcweb::Plugins::Marketplace::PackageArchive.new(
      path: package,
      source: "file:///reviewed/demo.zip",
      expected_sha256: "0" * 64
    )

    assert_raises(Mcweb::Plugins::Marketplace::IntegrityError) do
      archive.extract_to(destination)
    end
    refute destination.exist?
  end

  test "archive never removes a preexisting staging destination" do
    package = write_zip(
      "existing-destination.zip",
      "mcweb_plugin.yml" => manifest_yaml,
      "plugin.rb" => "safe"
    )
    destination = @temporary.join("operator-owned")
    destination.mkpath
    destination.join("keep.txt").write("keep")

    assert_raises(Mcweb::Plugins::Marketplace::PackageError) do
      archive_for(package).extract_to(destination)
    end
    assert_equal "keep", destination.join("keep.txt").read
  end

  private

  def archive_for(package)
    Mcweb::Plugins::Marketplace::PackageArchive.new(
      path: package,
      source: "file:///reviewed/#{package.basename}",
      expected_sha256: Digest::SHA256.file(package).hexdigest
    )
  end

  def write_zip(name, entries)
    path = @temporary.join(name)
    Zip::File.open(path, create: true) do |archive|
      entries.each do |entry_name, contents|
        archive.get_output_stream(entry_name) { |stream| stream.write(contents) }
      end
    end
    path
  end

  def manifest_yaml
    {
      "id" => "acme/demo",
      "name" => "Demo",
      "version" => "1.0.0",
      "api_version" => "1",
      "entrypoint" => "plugin.rb"
    }.to_yaml
  end
end
