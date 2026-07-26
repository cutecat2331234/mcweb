# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/manifest"
require "tmpdir"

class Mcweb::Plugins::ManifestCanonicalizerTest < ActiveSupport::TestCase
  GOLDEN_ATTRIBUTES = {
    id: "acme/demo",
    name: "示例插件",
    version: "1.2.3",
    api_version: "1",
    description: "第一行\n第二行 café",
    author: "Acme",
    homepage: "https://example.test/plugins/demo",
    requires: {
      "zeta/core" => ">= 2.0.0",
      "alpha/base" => "~> 1.0"
    },
    capabilities: [
      "forum.posts.write",
      "forum.events.read"
    ],
    contributions: {
      permissions: "config/permissions.yml"
    },
    entrypoint: "lib/demo.rb",
    setup: "db/setup.rb"
  }.freeze

  GOLDEN_JSON = <<~'JSON'.chomp.freeze
    {"id":"acme/demo","name":"示例插件","version":"1.2.3","api_version":"1","description":"第一行\n第二行 café","author":"Acme","homepage":"https://example.test/plugins/demo","requires":{"alpha/base":"~> 1.0","zeta/core":">= 2.0.0"},"capabilities":["forum.events.read","forum.posts.write"],"contributions":{"permissions":"config/permissions.yml"},"entrypoint":"lib/demo.rb","setup":"db/setup.rb"}
  JSON

  GOLDEN_SHA256 = "ed997e4dafc156db4add6d8e6b9f5483174c8a8a14bb445fce00b4d25a232a65"
  LEGACY_V1_SHA256 = "8bb0c2858398347741afce8ee8039114f41740bb028a0f471cd73c3e348b5e58"

  test "canonical representation has a fixed v1 field order and golden digest" do
    manifest = Mcweb::Plugins::Manifest.from_hash(
      GOLDEN_ATTRIBUTES,
      source_path: "C:/deployments/one/mcweb_plugin.yml"
    )

    assert_equal(
      %w[
        id name version api_version description author homepage requires
        capabilities contributions entrypoint setup
      ],
      manifest.canonical_hash.keys
    )
    assert_equal GOLDEN_JSON, manifest.canonical_json
    assert_equal Encoding::UTF_8, manifest.canonical_json.encoding
    assert_equal GOLDEN_SHA256, manifest.canonical_sha256
    assert_equal manifest.canonical_sha256, manifest.canonical_digest
    refute_includes manifest.canonical_hash, "source_path"

    exposed = [
      manifest.canonical_hash,
      *manifest.canonical_hash.keys,
      *manifest.canonical_hash.values.compact,
      *manifest.canonical_hash.fetch("requires").keys,
      *manifest.canonical_hash.fetch("requires").values,
      *manifest.canonical_hash.fetch("capabilities"),
      manifest.canonical_json,
      manifest.canonical_sha256
    ]
    exposed.each { |value| assert_predicate value, :frozen? }
  end

  test "semantically equivalent manifests have the same canonical digest" do
    reordered = GOLDEN_ATTRIBUTES.to_a.reverse.to_h.merge(
      name: "示例插件".unicode_normalize(:nfd),
      description: "第一行\r\n第二行 cafe\u0301",
      requires: GOLDEN_ATTRIBUTES.fetch(:requires).to_a.reverse.to_h,
      capabilities: GOLDEN_ATTRIBUTES.fetch(:capabilities).reverse
    )

    first = Mcweb::Plugins::Manifest.from_hash(
      GOLDEN_ATTRIBUTES,
      source_path: "C:/deployments/one/mcweb_plugin.yml"
    )
    second = Mcweb::Plugins::Manifest.from_hash(
      reordered,
      source_path: "D:/other-location/mcweb_plugin.yml"
    )

    assert_equal first.canonical_hash, second.canonical_hash
    assert_equal first.canonical_json, second.canonical_json
    assert_equal first.canonical_sha256, second.canonical_sha256
  end

  test "legacy v1 digest is unchanged when contributions are omitted" do
    legacy = Mcweb::Plugins::Manifest.from_hash(
      GOLDEN_ATTRIBUTES.except(:contributions)
    )

    refute_includes legacy.canonical_hash, "contributions"
    assert_equal LEGACY_V1_SHA256, legacy.canonical_sha256
  end

  test "UTF-8 BOM and source line endings do not affect a loaded manifest digest" do
    Dir.mktmpdir("mcweb-canonical-manifest") do |directory|
      first_path = File.join(directory, "first.yml")
      second_path = File.join(directory, "second.yml")
      yaml = <<~YAML
        id: acme/demo
        name: 示例插件
        version: 1.2.3
        api_version: "1"
        description: café
        requires:
          zeta/core: ">= 2.0.0"
          alpha/base: "~> 1.0"
        capabilities:
          - forum.posts.write
          - forum.events.read
      YAML
      reordered_yaml = <<~YAML
        capabilities:
          - forum.events.read
          - forum.posts.write
        requires:
          alpha/base: "~> 1.0"
          zeta/core: ">= 2.0.0"
        description: café
        api_version: "1"
        version: 1.2.3
        name: 示例插件
        id: acme/demo
      YAML

      File.binwrite(first_path, yaml)
      File.binwrite(second_path, "\uFEFF#{reordered_yaml.gsub("\n", "\r\n")}")

      first = Mcweb::Plugins::Manifest.load_file(first_path)
      second = Mcweb::Plugins::Manifest.load_file(second_path)

      assert_equal first.canonical_json, second.canonical_json
      assert_equal first.canonical_sha256, second.canonical_sha256
    end
  end

  test "semantic manifest changes alter the canonical digest" do
    original = Mcweb::Plugins::Manifest.from_hash(GOLDEN_ATTRIBUTES)
    changes = {
      version: "1.2.4",
      entrypoint: "lib/other.rb",
      setup: "db/other_setup.rb",
      contributions: { permissions: "config/other_permissions.yml" }
    }

    changes.each do |field, value|
      changed = Mcweb::Plugins::Manifest.from_hash(GOLDEN_ATTRIBUTES.merge(field => value))

      refute_equal original.canonical_sha256, changed.canonical_sha256, field.to_s
    end
  end

  test "minimal v1 manifests retain explicit canonical defaults" do
    manifest = Mcweb::Plugins::Manifest.from_hash({
      id: "acme/minimal",
      name: "Minimal",
      version: "1.0.0",
      api_version: "1"
    })

    assert_equal(
      {
        "id" => "acme/minimal",
        "name" => "Minimal",
        "version" => "1.0.0",
        "api_version" => "1",
        "description" => nil,
        "author" => nil,
        "homepage" => nil,
        "requires" => {},
        "capabilities" => [],
        "entrypoint" => nil,
        "setup" => nil
      },
      manifest.canonical_hash
    )
  end
end
