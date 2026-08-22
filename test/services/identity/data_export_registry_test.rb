# frozen_string_literal: true

require "test_helper"
require "zip"

module Identity
  class DataExportRegistryTest < ActiveSupport::TestCase
    test "registry validates stable keys contributor contract duplicates and freeze boundary" do
      registry = DataExportRegistry.new
      contributor = ->(context:) { DataExporting::Contribution.new(documents: { "sample.json" => [] }) }

      entry = registry.register(key: "sample.valid", contributor:)
      assert_equal "sample.valid", entry.key
      assert_raises(ArgumentError) do
        registry.register(key: "sample.valid", contributor:)
      end
      assert_raises(ArgumentError) do
        registry.register(key: "invalid", contributor:)
      end
      assert_raises(ArgumentError) do
        registry.register(key: "sample.incomplete", contributor: Object.new)
      end

      registry.freeze!
      assert_predicate registry, :frozen?
      assert_raises(FrozenError) do
        registry.register(key: "sample.late", contributor:)
      end
    end

    test "core catalog is frozen keeps CE order and permits unique downstream owners" do
      keys = DataExportCatalog.entries.map(&:key)
      ce_keys = %w[
        identity.profile identity.notifications community.content community.uploads commerce.account
        minecraft.accounts security.evidence_attachments
      ]

      assert_equal ce_keys, keys.select { |key| key.in?(ce_keys) }
      assert_equal keys.uniq, keys
      assert DataExportCatalog.registry_frozen?
    end

    test "archive exposes a versioned manifest with per-module and total counts" do
      registry = DataExportRegistry.new
      registry.register(
        key: "sample.profile",
        contributor: ->(context:) do
          DataExporting::Contribution.new(
            documents: { "sample/profile.json" => { "public_id" => context.user.public_id } }
          )
        end
      )
      registry.register(
        key: "sample.history",
        contributor: ->(context:) do
          DataExporting::Contribution.new(
            documents: { "sample/history.json" => [ { "id" => 1 }, { "id" => 2 } ] }
          )
        end
      )
      generated_at = Time.zone.parse("2026-08-22 12:00:00 UTC")
      user = Struct.new(:public_id).new("export-user")

      result = DataExportArchive.call(user:, generated_at:, entries: registry.entries)

      assert_predicate result, :success?
      manifest = result.value.fetch(:manifest)
      assert_equal 2, manifest.fetch("schema_version")
      assert_equal 1, manifest.dig("modules", "sample.profile", "record_count")
      assert_equal 2, manifest.dig("modules", "sample.history", "record_count")
      assert_equal 3, manifest.fetch("total_record_count")
      assert_equal %w[sample/profile.json sample/history.json], manifest.fetch("files")

      archived_manifest = nil
      Zip::File.open_buffer(result.value.fetch(:io).string) do |zip|
        archived_manifest = JSON.parse(zip.find_entry("manifest.json").get_input_stream.read)
      end
      assert_equal manifest, archived_manifest
    end

    test "invalid result path collision and contributor exception fail with a retryable public code" do
      user = Struct.new(:public_id).new("export-user")
      invalid_registry = DataExportRegistry.new
      invalid_registry.register(key: "sample.invalid", contributor: ->(context:) { Object.new })

      invalid_result = DataExportArchive.call(user:, entries: invalid_registry.entries)

      assert_predicate invalid_result, :failure?
      assert_equal "data_export_contributor_failed", invalid_result.code

      collision_registry = DataExportRegistry.new
      2.times do |index|
        collision_registry.register(
          key: "sample.collision_#{index}",
          contributor: ->(context:) do
            DataExporting::Contribution.new(documents: { "same.json" => [] })
          end
        )
      end

      collision_result = DataExportArchive.call(user:, entries: collision_registry.entries)

      assert_predicate collision_result, :failure?
      assert_equal "data_export_contributor_failed", collision_result.code

      raising_registry = DataExportRegistry.new
      raising_registry.register(
        key: "sample.raising",
        contributor: ->(context:) { raise "private failure detail" }
      )

      raising_result = DataExportArchive.call(user:, entries: raising_registry.entries)

      assert_predicate raising_result, :failure?
      assert_equal "data_export_contributor_failed", raising_result.code
      refute_includes raising_result.error, "private failure detail"
    end

    test "contributions reject traversal and reserved manifest paths" do
      assert_raises(ArgumentError) do
        DataExporting::Contribution.new(documents: { "../secret.json" => [] })
      end
      assert_raises(ArgumentError) do
        DataExporting::Contribution.new(documents: { "manifest.json" => [] })
      end
    end
  end
end
