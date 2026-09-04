# frozen_string_literal: true

require "test_helper"
require "zip"

module Identity
  class DataExportRegistryTest < ActiveSupport::TestCase
    setup { @archive_ios = [] }

    teardown do
      @archive_ios.each do |io|
        io.close!
      rescue StandardError
        nil
      end
    end

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
      assert_equal 3, manifest.fetch("schema_version")
      assert_equal 1, manifest.dig("modules", "sample.profile", "record_count")
      assert_equal 2, manifest.dig("modules", "sample.history", "record_count")
      assert_equal 3, manifest.fetch("total_record_count")
      assert_equal %w[sample/profile.json sample/history.json], manifest.fetch("files")

      archived_manifest = nil
      Zip::File.open_buffer(tracked_archive_io(result).read) do |zip|
        archived_manifest = JSON.parse(zip.find_entry("manifest.json").get_input_stream.read)
      end
      assert_equal manifest, archived_manifest
    end

    test "streaming documents are written as jsonl without materializing the record set" do
      yielded = []
      registry = DataExportRegistry.new
      registry.register(
        key: "sample.streaming",
        contributor: ->(context:) do
          document = DataExporting::StreamingDocument.new(declared_count: 3) do
            Enumerator.new do |records|
              3.times do |index|
                yielded << index
                records << { "id" => index, "user" => context.user.public_id }
              end
            end
          end
          DataExporting::Contribution.new(documents: { "sample/history.jsonl" => document })
        end
      )
      user = Struct.new(:public_id).new("stream-user")

      result = DataExportArchive.call(user:, entries: registry.entries)

      assert_predicate result, :success?
      assert_equal [ 0, 1, 2 ], yielded
      assert_equal 3, result.value.dig(:manifest, "total_record_count")
      Zip::File.open_buffer(tracked_archive_io(result).read) do |zip|
        rows = zip.find_entry("sample/history.jsonl").get_input_stream.each_line.map { |line| JSON.parse(line) }
        assert_equal [ 0, 1, 2 ], rows.pluck("id")
      end
    end

    test "stream iteration distinguishes producer failures from consumer io failures" do
      producer = DataExporting::StreamingDocument.new(declared_count: 1) do
        Enumerator.new { |_records| raise ArgumentError, "private producer failure" }
      end
      producer_error = assert_raises(DataExporting::StreamingDocument::IterationFailure) do
        producer.each_record.to_a
      end
      assert_equal "ArgumentError", producer_error.failure_class

      consumer = DataExporting::StreamingDocument.new(declared_count: 1) { [ { "id" => 1 } ] }
      assert_raises(Errno::ENOSPC) do
        consumer.each_record { |_record| raise Errno::ENOSPC }
      end
    end

    test "streaming object documents preserve the existing json shape and use actual counts" do
      registry = DataExportRegistry.new
      registry.register(
        key: "sample.object",
        contributor: ->(context:) do
          first = DataExporting::StreamingDocument.new(declared_count: 99, format: :json_array) do
            [ { "id" => 1, "user" => context.user.public_id } ]
          end
          second = DataExporting::StreamingDocument.new(declared_count: 0, format: :json_array) do
            [ { "id" => 2 }, { "id" => 3 } ]
          end
          document = DataExporting::StreamingObjectDocument.new(
            members: { "first" => first, "second" => second }
          )
          DataExporting::Contribution.new(documents: { "sample/object.json" => document })
        end
      )
      user = Struct.new(:public_id).new("object-user")

      result = DataExportArchive.call(user:, entries: registry.entries)

      assert_predicate result, :success?
      assert_equal 3, result.value.dig(:manifest, "total_record_count")
      Zip::File.open_buffer(tracked_archive_io(result).read) do |zip|
        document = JSON.parse(zip.find_entry("sample/object.json").get_input_stream.read)
        assert_equal [ 1 ], document.fetch("first").pluck("id")
        assert_equal [ 2, 3 ], document.fetch("second").pluck("id")
      end
    end

    test "nested streams and large escaped strings are emitted incrementally without changing json" do
      body = ("汉字\"\\\n" * 20_000)
      registry = DataExportRegistry.new
      registry.register(
        key: "sample.nested_stream",
        contributor: ->(context:) do
          nested = DataExporting::StreamingDocument.new(declared_count: 2, format: :json_array) do
            [ { "type" => "created" }, { "type" => "downloaded" } ]
          end
          outer = DataExporting::StreamingDocument.new(declared_count: 1, format: :json_array) do
            [ { "body" => body, "events" => nested, "user" => context.user.public_id } ]
          end
          DataExporting::Contribution.new(documents: { "sample/nested.json" => outer })
        end
      )
      user = Struct.new(:public_id).new("nested-stream-user")

      result = DataExportArchive.call(user:, entries: registry.entries)

      assert_predicate result, :success?
      Zip::File.open_buffer(tracked_archive_io(result).read) do |zip|
        row = JSON.parse(zip.find_entry("sample/nested.json").get_input_stream.read).sole
        assert_equal body, row.fetch("body")
        assert_equal %w[created downloaded], row.fetch("events").pluck("type")
      end
    end

    test "a streaming object document cannot be embedded inside another json value" do
      member = DataExporting::StreamingDocument.new(declared_count: 1, format: :json_array) do
        [ { "id" => 1 } ]
      end
      nested_object = DataExporting::StreamingObjectDocument.new(members: { "items" => member })

      result = export_result_for_payload(
        { "nested" => nested_object },
        key: "sample.nested_streaming_object"
      )

      assert_predicate result, :failure?
      assert_equal "data_export_contributor_failed", result.code
    end

    test "json string streaming preserves whitespace-only values and trailing whitespace" do
      whitespace_only = " \t\n  "
      trailing_whitespace = "kept \t\n  "
      payload = { "whitespace_only" => whitespace_only, "trailing_whitespace" => trailing_whitespace }

      result = export_result_for_payload(payload, key: "sample.whitespace_strings")

      assert_predicate result, :success?
      Zip::File.open_buffer(tracked_archive_io(result).read) do |zip|
        document = JSON.parse(zip.find_entry("sample/payload.json").get_input_stream.read)
        assert_equal whitespace_only, document.fetch("whitespace_only")
        assert_equal trailing_whitespace, document.fetch("trailing_whitespace")
      end
    end

    test "self-referential arrays and hashes are invalid contributor payloads" do
      circular_array = []
      circular_array << circular_array
      circular_hash = {}
      circular_hash["self"] = circular_hash

      [ circular_array, circular_hash ].each_with_index do |payload, index|
        error = assert_raises(DataExporting::Contribution::InvalidPayload) do
          DataExporting::Contribution.new(documents: { "sample/circular-#{index}.json" => payload })
        end
        assert_equal :circular_reference, error.reason

        result = export_result_for_payload(payload, key: "sample.circular_#{index}")

        assert_predicate result, :failure?
        assert_equal "data_export_contributor_failed", result.code
        refute_equal "data_export_resource_exhausted", result.code
      end
    end

    test "payload depth limit accepts the boundary and rejects deeper structures" do
      boundary_payload = nil
      DataExporting::Contribution::MAX_JSON_DEPTH.times { boundary_payload = [ boundary_payload ] }

      boundary_result = export_result_for_payload(boundary_payload, key: "sample.depth_boundary")

      assert_predicate boundary_result, :success?
      tracked_archive_io(boundary_result)

      too_deep_payload = [ boundary_payload ]
      error = assert_raises(DataExporting::Contribution::InvalidPayload) do
        DataExporting::Contribution.new(documents: { "sample/too-deep.json" => too_deep_payload })
      end
      assert_equal :maximum_depth, error.reason

      too_deep_result = export_result_for_payload(too_deep_payload, key: "sample.too_deep")

      assert_predicate too_deep_result, :failure?
      assert_equal "data_export_contributor_failed", too_deep_result.code
      refute_equal "data_export_resource_exhausted", too_deep_result.code
    end

    test "invalid string encoding is an invalid contributor payload" do
      invalid_string = "\xFF".b.force_encoding(Encoding::UTF_8)
      payload = { "value" => invalid_string }

      error = assert_raises(DataExporting::Contribution::InvalidPayload) do
        DataExporting::Contribution.new(documents: { "sample/invalid-encoding.json" => payload })
      end
      assert_includes %i[invalid_encoding invalid_json_value], error.reason

      result = export_result_for_payload(payload, key: "sample.invalid_encoding")

      assert_predicate result, :failure?
      assert_equal "data_export_contributor_failed", result.code
      refute_equal "data_export_resource_exhausted", result.code
    end

    test "invalid streamed payloads remove their failed archive tempfile" do
      circular_record = []
      circular_record << circular_record
      stream = DataExporting::StreamingDocument.new(declared_count: 1, format: :json_array) do
        [ circular_record ]
      end
      registry = DataExportRegistry.new
      registry.register(
        key: "sample.invalid_stream",
        contributor: ->(context:) do
          DataExporting::Contribution.new(documents: { "sample/invalid-stream.json" => stream })
        end
      )
      archive = DataExportTemporaryStorage.create
      archive_path = archive.path
      @archive_ios << archive

      result = DataExportTemporaryStorage.stub(:create, archive) do
        DataExportArchive.call(user: Struct.new(:public_id).new("invalid-stream-user"), entries: registry.entries)
      end

      assert_predicate result, :failure?
      assert_equal "data_export_contributor_failed", result.code
      refute File.exist?(archive_path)
    end

    test "zip io failures remain generation failures and remove their tempfile" do
      archive = DataExportTemporaryStorage.create
      archive_path = archive.path
      @archive_ios << archive
      registry = DataExportRegistry.new
      registry.register(
        key: "sample.zip_failure",
        contributor: ->(context:) do
          DataExporting::Contribution.new(documents: { "sample/zip-failure.json" => { "id" => context.user.public_id } })
        end
      )

      result = DataExportTemporaryStorage.stub(:create, archive) do
        Zip::OutputStream.stub(:open, ->(*) { raise Errno::ENOSPC }) do
          DataExportArchive.call(user: Struct.new(:public_id).new("zip-failure-user"), entries: registry.entries)
        end
      end

      assert_predicate result, :failure?
      assert_equal "data_export_generation_failed", result.code
      refute File.exist?(archive_path)
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

      lazy_registry = DataExportRegistry.new
      lazy_registry.register(
        key: "sample.lazy_raising",
        contributor: ->(context:) do
          stream = DataExporting::StreamingDocument.new(declared_count: 2, format: :json_array) do
            Enumerator.new do |records|
              records << { "user" => context.user.public_id }
              raise "private lazy failure detail"
            end
          end
          DataExporting::Contribution.new(documents: { "sample/lazy.json" => stream })
        end
      )

      lazy_result = DataExportArchive.call(user:, entries: lazy_registry.entries)

      assert_predicate lazy_result, :failure?
      assert_equal "data_export_contributor_failed", lazy_result.code
      refute_includes lazy_result.error, "private lazy failure detail"
    end

    test "archive generation fails safely before exceeding its uncompressed size budget" do
      previous_limit = ENV["MCWEB_DATA_EXPORT_MAX_UNCOMPRESSED_BYTES"]
      ENV["MCWEB_DATA_EXPORT_MAX_UNCOMPRESSED_BYTES"] = "8"
      registry = DataExportRegistry.new
      registry.register(
        key: "sample.oversized",
        contributor: ->(context:) do
          DataExporting::Contribution.new(
            documents: { "sample/oversized.json" => { "value" => context.user.public_id } }
          )
        end
      )
      user = Struct.new(:public_id).new("larger-than-eight-bytes")

      result = DataExportArchive.call(user:, entries: registry.entries)

      assert_predicate result, :failure?
      assert_equal "data_export_size_exceeded", result.code
    ensure
      if previous_limit.nil?
        ENV.delete("MCWEB_DATA_EXPORT_MAX_UNCOMPRESSED_BYTES")
      else
        ENV["MCWEB_DATA_EXPORT_MAX_UNCOMPRESSED_BYTES"] = previous_limit
      end
    end

    test "resource exhaustion fallbacks return a localized retryable code" do
      { "no_memory" => NoMemoryError, "system_stack" => SystemStackError }.each do |name, error_class|
        registry = DataExportRegistry.new
        registry.register(
          key: "sample.resource_exhausted_#{name}",
          contributor: ->(context:) { raise error_class, context.user.public_id }
        )
        user = Struct.new(:public_id).new("resource-exhausted-#{name}-user")

        result = DataExportArchive.call(user:, entries: registry.entries)

        assert_predicate result, :failure?
        assert_equal "data_export_resource_exhausted", result.code
        refute_includes result.error, "translation missing"
        refute_includes result.error, user.public_id
      end
    end

    test "contributions reject traversal and reserved manifest paths" do
      assert_raises(ArgumentError) do
        DataExporting::Contribution.new(documents: { "../secret.json" => [] })
      end
      assert_raises(ArgumentError) do
        DataExporting::Contribution.new(documents: { "manifest.json" => [] })
      end
      assert_raises(ArgumentError) do
        DataExporting::Contribution.new(documents: { "sample.jsonl" => [] })
      end
      assert_raises(ArgumentError) do
        stream = DataExporting::StreamingDocument.new(declared_count: 0, format: :json_array) { [] }
        DataExporting::Contribution.new(documents: { "sample.jsonl" => stream })
      end
      assert_raises(ArgumentError) do
        stream = DataExporting::StreamingDocument.new(declared_count: 0) { [] }
        DataExporting::StreamingObjectDocument.new(members: { "nested" => stream })
      end
    end

    private

    def export_result_for_payload(payload, key:)
      registry = DataExportRegistry.new
      registry.register(
        key:,
        contributor: ->(context:) do
          DataExporting::Contribution.new(documents: { "sample/payload.json" => payload })
        end
      )
      DataExportArchive.call(user: Struct.new(:public_id).new("payload-user"), entries: registry.entries)
    end

    def tracked_archive_io(result)
      io = result.value.fetch(:io)
      @archive_ios << io unless @archive_ios.include?(io)
      io
    end
  end
end
