# frozen_string_literal: true

require "zip"

module Identity
  class DataExportArchive < ApplicationService
    MANIFEST_SCHEMA_VERSION = 3
    DEFAULT_MAX_UNCOMPRESSED_BYTES = 2.gigabytes
    JSON_STRING_CHUNK_BYTES = 64.kilobytes

    def initialize(user:, generated_at: Time.current, entries: DataExportCatalog.entries)
      @user = user
      @generated_at = generated_at
      @entries = entries
    end

    def call
      archive = nil
      archive_handed_off = false
      contributions = build_contributions
      manifest = nil
      archive = DataExportTemporaryStorage.create
      archive.close

      module_file_counts = {}
      bytes_written = 0
      Zip::OutputStream.open(archive.path) do |zip|
        contributions.each do |module_key, contribution|
          module_file_counts[module_key] = {}
          bytes_written = write_contribution(
            zip,
            module_key:,
            contribution:,
            file_counts: module_file_counts.fetch(module_key),
            bytes_written:
          )
        end

        manifest = build_manifest(contributions, module_file_counts:)
        zip.put_next_entry("manifest.json")
        write_json_value(zip, manifest, bytes_written:, depth: 0, ancestors: {})
      end

      archive.open
      archive.binmode
      archive.rewind

      result = ServiceResult.success(
        io: archive,
        manifest:
      )
      archive_handed_off = true
      result
    rescue ContributorFailure => e
      Rails.logger.error("data export contributor failed: #{e.module_key} (#{e.failure_class})")
      ServiceResult.failure(error: "data_export_contributor_failed", code: "data_export_contributor_failed")
    rescue ExportSizeExceeded
      Rails.logger.warn("data export generation stopped at the configured uncompressed size limit")
      ServiceResult.failure(error: "data_export_size_exceeded", code: "data_export_size_exceeded")
    rescue NoMemoryError, SystemStackError
      ServiceResult.failure(error: "data_export_resource_exhausted", code: "data_export_resource_exhausted")
    rescue StandardError => e
      Rails.logger.error("data export generation failed: #{e.class}")
      ServiceResult.failure(error: "data_export_generation_failed", code: "data_export_generation_failed")
    ensure
      cleanup_archive(archive) if archive && !archive_handed_off
    end

    private

    def build_contributions
      context = DataExporting::Context.new(user: @user, generated_at: @generated_at)
      documents = {}

      @entries.each_with_object({}) do |entry, result|
        contribution = entry.contributor.call(context:)
        unless contribution.is_a?(DataExporting::Contribution)
          raise ContributorFailure.new(module_key: entry.key, failure_class: "invalid_contract")
        end

        duplicate_path = contribution.documents.keys.find { |path| documents.key?(path) }
        if duplicate_path
          raise ContributorFailure.new(module_key: entry.key, failure_class: "duplicate_path")
        end

        contribution.documents.each_key { |path| documents[path] = entry.key }
        result[entry.key] = contribution
      rescue ContributorFailure
        raise
      rescue DataExporting::Contribution::InvalidPayload => e
        raise ContributorFailure.new(module_key: entry.key, failure_class: e.class.name), cause: e
      rescue StandardError => e
        raise ContributorFailure.new(module_key: entry.key, failure_class: e.class.name), cause: e
      end
    end

    def build_manifest(contributions, module_file_counts:)
      modules = contributions.each_with_object({}) do |(module_key, contribution), result|
        result[module_key] = contribution.manifest(
          file_counts: module_file_counts.fetch(module_key)
        )
      end
      {
        "schema_version" => MANIFEST_SCHEMA_VERSION,
        "generated_at" => @generated_at.iso8601,
        "user_public_id" => @user.public_id,
        "modules" => modules,
        "files" => modules.values.flat_map { |mod| mod.fetch("files").map { |file| file.fetch("path") } },
        "total_record_count" => modules.values.sum { |mod| mod.fetch("record_count") }
      }
    end

    def write_contribution(zip, module_key:, contribution:, file_counts:, bytes_written:)
      contribution.documents.each do |path, payload|
        zip.put_next_entry(path)
        count, bytes_written = write_document(zip, payload, bytes_written:)
        file_counts[path] = count
      end
      bytes_written
    rescue DataExporting::StreamingDocument::IterationFailure => e
      raise ContributorFailure.new(module_key:, failure_class: e.failure_class), cause: e
    rescue DataExporting::Contribution::InvalidPayload => e
      raise ContributorFailure.new(module_key:, failure_class: e.class.name), cause: e
    end

    def write_document(zip, payload, bytes_written:)
      DataExporting::Contribution.validate_payload!(payload)
      ancestors = {}
      if payload.is_a?(DataExporting::StreamingObjectDocument)
        write_streaming_object(zip, payload, bytes_written:, depth: 0, ancestors:)
      elsif payload.is_a?(DataExporting::StreamingDocument)
        if payload.jsonl?
          write_streaming_jsonl(zip, payload, bytes_written:, depth: 0, ancestors:)
        else
          write_streaming_json_array(zip, payload, bytes_written:, depth: 0, ancestors:)
        end
      elsif payload.is_a?(Array)
        write_json_array(zip, payload, bytes_written:, depth: 0, ancestors:)
      else
        bytes_written = write_json_value(zip, payload, bytes_written:, depth: 0, ancestors:)
        [ 1, bytes_written ]
      end
    end

    def write_streaming_object(zip, document, bytes_written:, depth:, ancestors:)
      with_json_container(document, depth:, ancestors:) do |next_depth|
        count = 0
        bytes_written = write_chunk(zip, "{", bytes_written:)
        document.members.each_with_index do |(key, member), index|
          bytes_written = write_chunk(zip, ",", bytes_written:) if index.positive?
          bytes_written = write_json_value(zip, key, bytes_written:, depth: next_depth, ancestors:)
          bytes_written = write_chunk(zip, ":", bytes_written:)
          member_count, bytes_written = write_streaming_json_array(
            zip,
            member,
            bytes_written:,
            depth: next_depth,
            ancestors:
          )
          count += member_count
        end
        bytes_written = write_chunk(zip, "}", bytes_written:)
        [ count, bytes_written ]
      end
    end

    def write_streaming_jsonl(zip, document, bytes_written:, depth:, ancestors:)
      count = 0
      document.each_record do |record|
        DataExporting::Contribution.validate_payload!(record)
        bytes_written = write_json_value(zip, record, bytes_written:, depth:, ancestors:)
        bytes_written = write_chunk(zip, "\n", bytes_written:)
        count += 1
      end

      [ count, bytes_written ]
    end

    def write_streaming_json_array(zip, document, bytes_written:, depth:, ancestors:)
      with_json_container(document, depth:, ancestors:) do |next_depth|
        count = 0
        bytes_written = write_chunk(zip, "[", bytes_written:)
        document.each_record do |record|
          DataExporting::Contribution.validate_payload!(record)
          bytes_written = write_chunk(zip, ",", bytes_written:) if count.positive?
          bytes_written = write_json_value(zip, record, bytes_written:, depth: next_depth, ancestors:)
          count += 1
        end
        bytes_written = write_chunk(zip, "]", bytes_written:)
        [ count, bytes_written ]
      end
    end

    def write_json_array(zip, records, bytes_written:, depth:, ancestors:)
      with_json_container(records, depth:, ancestors:) do |next_depth|
        bytes_written = write_chunk(zip, "[", bytes_written:)
        records.each_with_index do |record, index|
          bytes_written = write_chunk(zip, ",", bytes_written:) if index.positive?
          bytes_written = write_json_value(zip, record, bytes_written:, depth: next_depth, ancestors:)
        end
        bytes_written = write_chunk(zip, "]", bytes_written:)
        [ records.length, bytes_written ]
      end
    end

    def write_json_value(zip, value, bytes_written:, depth:, ancestors:)
      case value
      when DataExporting::StreamingObjectDocument
        raise DataExporting::Contribution::InvalidPayload.new(reason: :nested_streaming_object)
      when DataExporting::StreamingDocument
        if value.jsonl?
          raise DataExporting::Contribution::InvalidPayload.new(reason: :nested_jsonl_stream)
        end

        _count, bytes_written = write_streaming_json_array(zip, value, bytes_written:, depth:, ancestors:)
        bytes_written
      when Hash
        with_json_container(value, depth:, ancestors:) do |next_depth|
          bytes_written = write_chunk(zip, "{", bytes_written:)
          value.each_with_index do |(key, member), index|
            bytes_written = write_chunk(zip, ",", bytes_written:) if index.positive?
            bytes_written = write_json_string(zip, json_key_string(key), bytes_written:)
            bytes_written = write_chunk(zip, ":", bytes_written:)
            bytes_written = write_json_value(zip, member, bytes_written:, depth: next_depth, ancestors:)
          end
          write_chunk(zip, "}", bytes_written:)
        end
      when Array
        with_json_container(value, depth:, ancestors:) do |next_depth|
          bytes_written = write_chunk(zip, "[", bytes_written:)
          value.each_with_index do |member, index|
            bytes_written = write_chunk(zip, ",", bytes_written:) if index.positive?
            bytes_written = write_json_value(zip, member, bytes_written:, depth: next_depth, ancestors:)
          end
          write_chunk(zip, "]", bytes_written:)
        end
      when String
        write_json_string(zip, value, bytes_written:)
      else
        write_chunk(zip, generate_json_payload(value), bytes_written:)
      end
    end

    def with_json_container(container, depth:, ancestors:)
      if depth >= DataExporting::Contribution::MAX_JSON_DEPTH
        raise DataExporting::Contribution::InvalidPayload.new(reason: :maximum_depth)
      end

      identity = container.object_id
      if ancestors.key?(identity)
        raise DataExporting::Contribution::InvalidPayload.new(reason: :circular_reference)
      end

      ancestors[identity] = true
      begin
        yield depth + 1
      ensure
        ancestors.delete(identity)
      end
    end

    def write_json_string(zip, value, bytes_written:)
      bytes_written = write_chunk(zip, '"', bytes_written:)
      buffer = +""
      value.each_char do |character|
        buffer << character
        next if buffer.bytesize < JSON_STRING_CHUNK_BYTES

        bytes_written = write_json_string_fragment(zip, buffer, bytes_written:)
        buffer.clear
      end
      bytes_written = write_json_string_fragment(zip, buffer, bytes_written:) unless buffer.empty?
      write_chunk(zip, '"', bytes_written:)
    end

    def write_json_string_fragment(zip, fragment, bytes_written:)
      encoded = generate_json_payload(fragment)
      write_chunk(zip, encoded.byteslice(1, encoded.bytesize - 2), bytes_written:)
    end

    def json_key_string(key)
      key.to_s
    rescue StandardError => error
      raise DataExporting::Contribution::InvalidPayload.new(reason: :invalid_key), cause: error
    end

    def generate_json_payload(value)
      JSON.generate(value)
    rescue StandardError => error
      raise DataExporting::Contribution::InvalidPayload.new(reason: :invalid_json_value), cause: error
    end

    def write_chunk(zip, chunk, bytes_written:)
      total = bytes_written + chunk.bytesize
      raise ExportSizeExceeded if total > max_uncompressed_bytes

      zip.write(chunk)
      total
    end

    def max_uncompressed_bytes
      @max_uncompressed_bytes ||= begin
        configured = Integer(ENV["MCWEB_DATA_EXPORT_MAX_UNCOMPRESSED_BYTES"], exception: false)
        configured&.positive? ? configured : DEFAULT_MAX_UNCOMPRESSED_BYTES
      end
    end

    def cleanup_archive(archive)
      return unless archive

      archive.close!
    rescue StandardError
      nil
    end

    class ExportSizeExceeded < StandardError; end

    class ContributorFailure < StandardError
      attr_reader :module_key, :failure_class

      def initialize(module_key:, failure_class:)
        @module_key = module_key
        @failure_class = failure_class
        super("data export contributor failed")
      end
    end
  end
end
