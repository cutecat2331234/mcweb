# frozen_string_literal: true

require "fileutils"
require "pathname"
require "tempfile"

module Identity
  class DataExportTemporaryStorage
    DEFAULT_ROOT = Rails.root.join("tmp", "data-exports").freeze
    FILE_PREFIX = "archive-"
    FILE_SUFFIX = ".zip"
    ORPHAN_AFTER = 6.hours

    class << self
      def create(root: DEFAULT_ROOT)
        directory = prepare_directory!(root)
        tempfile = Tempfile.new([ FILE_PREFIX, FILE_SUFFIX ], directory.to_s)
        tempfile.binmode
        File.chmod(0o600, tempfile.path)
        tempfile
      rescue StandardError
        tempfile&.close!
        raise
      end

      def cleanup_orphans!(root: DEFAULT_ROOT, now: Time.current, older_than: ORPHAN_AFTER)
        directory = prepare_directory!(root)
        cutoff = now.to_time - normalized_age(older_than)
        result = { scanned: 0, removed: 0, retained: 0, failed: 0 }

        Dir.each_child(directory) do |name|
          next unless managed_filename?(name)

          result[:scanned] += 1
          cleanup_candidate(directory.join(name), cutoff:, result:)
        end

        result.freeze
      end

      private

      def prepare_directory!(root)
        directory = Pathname(root).expand_path
        FileUtils.mkdir_p(directory, mode: 0o700)
        if File.symlink?(directory) || !File.directory?(directory)
          raise ArgumentError, "data_export_temporary_directory_invalid"
        end

        File.chmod(0o700, directory)
        directory
      end

      def normalized_age(value)
        seconds = value.to_i
        raise ArgumentError, "data_export_temporary_retention_invalid" unless seconds.positive?

        seconds
      end

      def managed_filename?(name)
        name.start_with?(FILE_PREFIX) && name.end_with?(FILE_SUFFIX)
      end

      def cleanup_candidate(path, cutoff:, result:)
        stat = File.lstat(path)
        unless stat.file? && !stat.symlink?
          result[:retained] += 1
          return
        end
        if stat.mtime > cutoff
          result[:retained] += 1
          return
        end

        File.unlink(path)
        result[:removed] += 1
      rescue Errno::ENOENT
        nil
      rescue StandardError => error
        result[:failed] += 1
        Rails.logger.warn("data export temporary cleanup failed: #{error.class}")
      end
    end
  end
end
