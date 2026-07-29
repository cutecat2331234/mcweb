# frozen_string_literal: true

require "digest"
require "find"
require "pathname"
require "set"

module Mcweb
  module Plugins
    module Marketplace
      class FileHealth
        MAX_FILES = 10_000
        MAX_FILE_BYTES = 64 * 1024 * 1024
        ALGORITHM = "sha256"

        Result = Data.define(
          :status, :expected_count, :actual_count, :missing, :modified, :unknown
        ) do
          def healthy?
            status == "healthy"
          end

          def to_h
            {
              status:,
              expected_count:,
              actual_count:,
              missing:,
              modified:,
              unknown:
            }.freeze
          end
        end

        class << self
          def manifest(directory, exclude_paths: [])
            root = normalized_root(directory)
            excluded = normalize_excluded_paths(exclude_paths)
            files = file_entries(root, excluded:).map do |path|
              relative = relative_path(path, root)
              {
                "path" => relative,
                "size" => path.size,
                "sha256" => Digest::SHA256.file(path).hexdigest
              }.freeze
            end
            {
              "algorithm" => ALGORITHM,
              "files" => files.freeze
            }.freeze
          end

          def check(directory:, expected:, exclude_paths: [])
            excluded = normalize_excluded_paths(exclude_paths)
            expected_files = normalize_expected(expected).reject do |entry|
              excluded.include?(entry.fetch("path"))
            end
            actual = manifest(directory, exclude_paths: excluded.to_a)
              .fetch("files")
              .to_h { |entry| [ entry.fetch("path"), entry ] }
            expected_by_path = expected_files.to_h { |entry| [ entry.fetch("path"), entry ] }
            missing = (expected_by_path.keys - actual.keys).sort
            unknown = (actual.keys - expected_by_path.keys).sort
            modified = (expected_by_path.keys & actual.keys).select do |path|
              expected_entry = expected_by_path.fetch(path)
              actual_entry = actual.fetch(path)
              expected_entry.fetch("size") != actual_entry.fetch("size") ||
                expected_entry.fetch("sha256") != actual_entry.fetch("sha256")
            end.sort
            status = if missing.empty? && modified.empty? && unknown.empty?
              "healthy"
            else
              "changed"
            end
            Result.new(
              status:,
              expected_count: expected_by_path.length,
              actual_count: actual.length,
              missing: missing.freeze,
              modified: modified.freeze,
              unknown: unknown.freeze
            )
          rescue Errno::ENOENT
            Result.new(
              status: "missing",
              expected_count: Array(expected&.fetch("files", [])).length,
              actual_count: 0,
              missing: Array(expected&.fetch("files", [])).filter_map { |entry| entry["path"] }.sort.freeze,
              modified: [].freeze,
              unknown: [].freeze
            )
          rescue StandardError
            Result.new(
              status: "unavailable",
              expected_count: 0,
              actual_count: 0,
              missing: [].freeze,
              modified: [].freeze,
              unknown: [].freeze
            )
          end

          private

          def normalized_root(directory)
            root = Pathname(directory).expand_path
            raise LifecycleError, "plugin directory does not exist" unless root.directory?

            root.realpath
          end

          def file_entries(root, excluded:)
            files = []
            Find.find(root.to_s) do |entry|
              path = Pathname(entry)
              next if path == root
              raise IntegrityError, "plugin files must not contain symlinks" if path.symlink?
              next if path.directory?
              raise IntegrityError, "plugin file tree contains an unsupported entry" unless path.file?
              raise IntegrityError, "plugin file exceeds the health-check limit" if path.size > MAX_FILE_BYTES
              next if excluded.include?(relative_path(path, root))

              files << path
              raise IntegrityError, "plugin file tree contains too many files" if files.length > MAX_FILES
            end
            files.sort_by { |path| relative_path(path, root) }
          end

          def relative_path(path, root)
            path.realpath.relative_path_from(root).to_s.tr("\\", "/")
          rescue ArgumentError
            raise IntegrityError, "plugin file escaped its managed directory"
          end

          def normalize_excluded_paths(paths)
            Array(paths).each_with_object(Set.new) do |value, result|
              path = Pathname(value.to_s.tr("\\", "/")).cleanpath
              if path.absolute? || path.to_s == "." || path.each_filename.first == ".."
                raise IntegrityError, "excluded plugin file path must remain inside the plugin directory"
              end

              result << path.to_s.tr("\\", "/")
            end.freeze
          rescue ArgumentError
            raise IntegrityError, "excluded plugin file path is invalid"
          end

          def normalize_expected(expected)
            unless expected.is_a?(Hash) && expected["algorithm"] == ALGORITHM &&
                expected["files"].is_a?(Array)
              raise IntegrityError, "plugin file manifest is unavailable"
            end

            seen = {}
            expected["files"].map do |entry|
              unless entry.is_a?(Hash) &&
                  entry["path"].is_a?(String) &&
                  entry["size"].is_a?(Integer) &&
                  entry["sha256"].to_s.match?(/\A[0-9a-f]{64}\z/)
                raise IntegrityError, "plugin file manifest is invalid"
              end
              path = Pathname(entry["path"]).cleanpath
              if path.absolute? || path.each_filename.any? { |part| part == ".." }
                raise IntegrityError, "plugin file manifest path is invalid"
              end
              normalized = path.to_s.tr("\\", "/")
              raise IntegrityError, "plugin file manifest contains duplicates" if seen[normalized]

              seen[normalized] = true
              {
                "path" => normalized.freeze,
                "size" => entry["size"],
                "sha256" => entry["sha256"].downcase.freeze
              }.freeze
            end.freeze
          end
        end
      end
    end
  end
end
