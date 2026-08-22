# frozen_string_literal: true

require "zip"

module Identity
  class DataExportArchive < ApplicationService
    MANIFEST_SCHEMA_VERSION = 2

    def initialize(user:, generated_at: Time.current, entries: DataExportCatalog.entries)
      @user = user
      @generated_at = generated_at
      @entries = entries
    end

    def call
      contributions = build_contributions
      manifest = build_manifest(contributions)
      documents = { "manifest.json" => manifest }
      contributions.each_value { |contribution| documents.merge!(contribution.documents) }
      archive = Zip::OutputStream.write_buffer do |zip|
        documents.each do |path, payload|
          zip.put_next_entry(path)
          zip.write(JSON.pretty_generate(payload))
        end
      end
      archive.rewind

      ServiceResult.success(
        io: archive,
        manifest:
      )
    rescue ContributorFailure => e
      Rails.logger.error("data export contributor failed: #{e.module_key} (#{e.failure_class})")
      ServiceResult.failure(error: "data_export_contributor_failed", code: "data_export_contributor_failed")
    rescue StandardError => e
      Rails.logger.error("data export generation failed: #{e.class}")
      ServiceResult.failure(error: "data_export_generation_failed", code: "data_export_generation_failed")
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
      rescue StandardError => e
        raise ContributorFailure.new(module_key: entry.key, failure_class: e.class.name), cause: e
      end
    end

    def build_manifest(contributions)
      modules = contributions.transform_values(&:manifest)
      {
        "schema_version" => MANIFEST_SCHEMA_VERSION,
        "generated_at" => @generated_at.iso8601,
        "user_public_id" => @user.public_id,
        "modules" => modules,
        "files" => modules.values.flat_map { |mod| mod.fetch("files").map { |file| file.fetch("path") } },
        "total_record_count" => modules.values.sum { |mod| mod.fetch("record_count") }
      }
    end

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
