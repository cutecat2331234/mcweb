#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require_relative "../lib/mcweb/disaster_recovery/object_archive"

module ObjectStorageArchiveCommand
  class << self
    def run(arguments)
      command = arguments.shift
      options = parse_options(arguments)
      backup_store = Mcweb::DisasterRecovery::ObjectArchive::Store.from_environment(
        "MCWEB_BACKUP_S3"
      )
      archive = Mcweb::DisasterRecovery::ObjectArchive.new(backup_store:)
      expected_backup = ENV["MCWEB_OBJECT_ARCHIVE_EXPECTED_BACKUP_BUCKET"]
      if expected_backup && backup_store.bucket != expected_backup
        raise Mcweb::DisasterRecovery::ObjectArchive::Error, "backup_store_mismatch"
      end

      count = case command
      when "snapshot"
        snapshot(archive, options)
      when "verify"
        archive.verify(load_inventory(options))
      when "restore"
        target_store = Mcweb::DisasterRecovery::ObjectArchive::Store.from_environment(
          "MCWEB_RESTORE_S3"
        )
        archive.restore(
          load_inventory(options),
          target_store:,
          source_bucket: ENV["MCWEB_OBJECT_ARCHIVE_EXPECTED_SOURCE_BUCKET"]
        )
      else
        raise Mcweb::DisasterRecovery::ObjectArchive::Error, "object_archive_command_invalid"
      end

      puts "Object archive #{command} completed: object_count=#{count}"
    end

    private

    def parse_options(arguments)
      options = {}
      OptionParser.new do |parser|
        parser.on("--inventory PATH") { |value| options[:inventory] = value }
        parser.on("--backup-id ID") { |value| options[:backup_id] = value }
      end.parse!(arguments)
      raise Mcweb::DisasterRecovery::ObjectArchive::Error, "object_archive_argument_invalid" if arguments.any?

      inventory = options[:inventory].to_s
      unless File.absolute_path(inventory) == inventory && !inventory.match?(/[\r\n]/)
        raise Mcweb::DisasterRecovery::ObjectArchive::Error, "object_inventory_path_invalid"
      end

      options
    rescue OptionParser::ParseError
      raise Mcweb::DisasterRecovery::ObjectArchive::Error, "object_archive_argument_invalid"
    end

    def snapshot(archive, options)
      backup_id = options[:backup_id].to_s
      unless backup_id.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]*\z/)
        raise Mcweb::DisasterRecovery::ObjectArchive::Error, "backup_id_invalid"
      end

      backup_prefix = ENV.fetch("MCWEB_BACKUP_S3_PREFIX", "mcweb-backups")
      validate_prefix!(backup_prefix)
      source_bucket = ENV.fetch("MCWEB_S3_BUCKET", "")
      if source_bucket.empty? || source_bucket.match?(/[\r\n]/)
        raise Mcweb::DisasterRecovery::ObjectArchive::Error, "source_bucket_missing"
      end
      if archive.backup_bucket == source_bucket
        raise Mcweb::DisasterRecovery::ObjectArchive::Error, "backup_bucket_matches_source"
      end

      require_relative "../config/environment"
      count = 0
      File.open(options.fetch(:inventory), "wb", 0o600) do |inventory|
        ActiveStorage::Blob.order(:id).find_each do |blob|
          backup_key = [ backup_prefix, backup_id, "objects", blob.key ].join("/")
          inventory.puts(JSON.generate(archive.snapshot(blob:, source_bucket:, backup_key:)))
          inventory.flush
          count += 1
        end
      end
      count
    end

    def load_inventory(options)
      inventory = Mcweb::DisasterRecovery::ObjectArchive::Inventory.load(options.fetch(:inventory))
      expected_source = ENV["MCWEB_OBJECT_ARCHIVE_EXPECTED_SOURCE_BUCKET"]
      expected_backup = ENV["MCWEB_OBJECT_ARCHIVE_EXPECTED_BACKUP_BUCKET"]
      inventory.each do |record|
        if expected_source && record.fetch("source_bucket") != expected_source
          raise Mcweb::DisasterRecovery::ObjectArchive::Error, "object_inventory_source_mismatch"
        end
        if expected_backup && record.fetch("snapshot_bucket") != expected_backup
          raise Mcweb::DisasterRecovery::ObjectArchive::Error, "object_inventory_backup_mismatch"
        end
      end
      inventory
    rescue KeyError
      raise Mcweb::DisasterRecovery::ObjectArchive::Error, "object_archive_argument_invalid"
    end

    def validate_prefix!(prefix)
      segments = prefix.split("/")
      valid = prefix.bytesize.between?(1, 512) &&
        prefix.match?(Mcweb::DisasterRecovery::ObjectArchive::KEY_PATTERN) &&
        segments.none? { |segment| segment.empty? || [ ".", ".." ].include?(segment) }
      raise Mcweb::DisasterRecovery::ObjectArchive::Error, "backup_prefix_invalid" unless valid
    end
  end
end

begin
  ObjectStorageArchiveCommand.run(ARGV)
rescue Mcweb::DisasterRecovery::ObjectArchive::Error => error
  warn "Object archive failed: #{error.code}"
  exit 70
rescue Aws::Errors::ServiceError => error
  warn "Object archive failed: object_store_unavailable (#{error.class.name})"
  exit 69
rescue StandardError => error
  warn "Object archive failed: object_archive_internal_error (#{error.class.name})"
  exit 70
end
