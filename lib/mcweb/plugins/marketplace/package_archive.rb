# frozen_string_literal: true

require "digest"
require "fileutils"
require "pathname"
require "stringio"
require "zip"
require_relative "error"
require_relative "package_source"

module Mcweb
  module Plugins
    module Marketplace
      class PackageArchive
        MAX_ARCHIVE_BYTES = 64 * 1024 * 1024
        MAX_ENTRIES = 5_000
        MAX_ENTRY_BYTES = 32 * 1024 * 1024
        MAX_UNCOMPRESSED_BYTES = 256 * 1024 * 1024
        MAX_COMPRESSION_RATIO = 200
        MAX_PATH_BYTES = 4_096
        MAX_COMPONENT_BYTES = 255
        MANIFEST_NAME = "mcweb_plugin.yml"
        METADATA_NAME = "mcweb_package.yml"
        FORBIDDEN_GIT_NAMES = %w[.git .gitconfig .git-credentials .gitmodules].freeze
        WINDOWS_FORBIDDEN_PATTERN = /[<>:"|?*]/
        WINDOWS_RESERVED_NAMES = (
          %w[con prn aux nul] +
          (1..9).flat_map { |number| [ "com#{number}", "lpt#{number}" ] }
        ).freeze
        SHA256_PATTERN = /\A[0-9a-f]{64}\z/i

        attr_reader :path, :source, :expected_sha256, :sha256

        def initialize(path:, source:, expected_sha256:)
          @path = Pathname(path).expand_path
          @source = source.is_a?(PackageSource) ? source : PackageSource.new(source)
          @expected_sha256 = expected_sha256.to_s.downcase.freeze
          raise IntegrityError, "expected SHA-256 must be 64 hexadecimal characters" unless @expected_sha256.match?(SHA256_PATTERN)
        end

        def extract_to(destination)
          verify_file!
          destination = Pathname(destination).expand_path
          raise PackageError, "staging destination already exists" if destination.exist?

          FileUtils.mkdir_p(destination, mode: 0o700)
          created_destination = true
          Zip::File.open_buffer(StringIO.new(@archive_bytes)) do |archive|
            validated_entries(archive).each { |entry| extract_entry(entry, destination) }
          end
          destination
        rescue Zip::Error => e
          FileUtils.rm_rf(destination) if created_destination && destination&.exist?
          raise PackageError, "invalid ZIP plugin package: #{e.message}"
        rescue StandardError
          FileUtils.rm_rf(destination) if created_destination && destination&.exist?
          raise
        ensure
          @archive_bytes = nil
        end

        private

        def verify_file!
          File.open(path, "rb") do |file|
            @archive_bytes = file.read(MAX_ARCHIVE_BYTES + 1)
          end
          raise PackageError, "plugin package is empty" if @archive_bytes.empty?
          if @archive_bytes.bytesize > MAX_ARCHIVE_BYTES
            raise PackageError, "plugin package exceeds #{MAX_ARCHIVE_BYTES} bytes"
          end

          @archive_bytes.freeze
          @sha256 = Digest::SHA256.hexdigest(@archive_bytes).freeze
          raise IntegrityError, "plugin package SHA-256 does not match" unless secure_digest_match?(sha256, expected_sha256)
        rescue Errno::ENOENT
          raise PackageError, "plugin package does not exist"
        rescue SystemCallError => e
          raise PackageError, "plugin package cannot be read: #{e.message}"
        end

        def validated_entries(archive)
          entries = archive.entries
          raise PackageError, "plugin package contains too many entries" if entries.length > MAX_ENTRIES
          raise PackageError, "plugin package is empty" if entries.empty?

          seen = {}
          total_size = 0
          normalized = entries.map do |entry|
            name = validate_entry!(entry)
            collision_key = name.unicode_normalize(:nfc).downcase
            raise PackageError, "plugin package contains colliding paths" if seen.key?(collision_key)

            seen[collision_key] = true
            total_size += entry.size
            if total_size > MAX_UNCOMPRESSED_BYTES
              raise PackageError, "plugin package expands beyond #{MAX_UNCOMPRESSED_BYTES} bytes"
            end
            [ entry, name ]
          end

          names = normalized.map(&:last)
          manifests = names.select { |name| File.basename(name) == MANIFEST_NAME }
          unless manifests == [ MANIFEST_NAME ]
            raise PackageError, "plugin package must contain exactly one root #{MANIFEST_NAME}"
          end
          metadata = names.select { |name| File.basename(name) == METADATA_NAME }
          if metadata.length > 1 || (metadata.one? && metadata.first != METADATA_NAME)
            raise PackageError, "#{METADATA_NAME} must be unique and at the package root"
          end

          normalized
        end

        def validate_entry!(entry)
          name = entry.name.to_s.dup
          name.force_encoding(Encoding::UTF_8)
          raise PackageError, "plugin package path must be valid UTF-8" unless name.valid_encoding?
          raise PackageError, "plugin package path is too long" if name.bytesize > MAX_PATH_BYTES
          raise PackageError, "plugin package path contains a NUL byte" if name.include?("\0")
          raise PackageError, "plugin package path contains control characters" if name.match?(/[[:cntrl:]]/)
          raise PackageError, "plugin package paths must use forward slashes" if name.include?("\\")
          raise PackageError, "plugin package path is absolute" if name.start_with?("/") || name.match?(/\A[A-Za-z]:/)
          raise PackageError, "plugin package contains a symbolic link" if entry.symlink?
          unless entry.directory? || entry.ftype == :file
            raise PackageError, "plugin package contains an unsupported entry type"
          end

          name = name.delete_suffix("/") if entry.directory?
          parts = name.split("/")
          if parts.empty? || parts.any? { |part| part.empty? || part == "." || part == ".." }
            raise PackageError, "plugin package path is not normalized"
          end
          if parts.any? { |part| invalid_portable_component?(part) }
            raise PackageError, "plugin package path is not portable"
          end
          if parts.any? { |part| FORBIDDEN_GIT_NAMES.include?(part.downcase) }
            raise PackageError, "plugin package must not contain Git metadata"
          end
          raise PackageError, "plugin package entry is too large" if entry.size > MAX_ENTRY_BYTES
          if entry.compressed_size.zero? && entry.size.positive?
            raise PackageError, "plugin package entry has an invalid compressed size"
          end
          if entry.compressed_size.positive? && (entry.size.to_f / entry.compressed_size) > MAX_COMPRESSION_RATIO
            raise PackageError, "plugin package entry exceeds the compression ratio limit"
          end

          name.freeze
        end

        def invalid_portable_component?(component)
          return true if component.bytesize > MAX_COMPONENT_BYTES
          return true if component.end_with?(".", " ")
          return true if component.match?(WINDOWS_FORBIDDEN_PATTERN)

          stem = component.split(".", 2).first.sub(/[ .]+\z/, "").downcase
          WINDOWS_RESERVED_NAMES.include?(stem)
        end

        def extract_entry(entry_and_name, destination)
          entry, name = entry_and_name
          target = destination.join(*name.split("/"))
          ensure_contained!(target, destination)
          if entry.directory?
            FileUtils.mkdir_p(target, mode: 0o755)
            return
          end

          FileUtils.mkdir_p(target.dirname, mode: 0o755)
          entry.get_input_stream do |input|
            File.open(target, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |output|
              written = IO.copy_stream(input, output, entry.size + 1)
              raise PackageError, "plugin package entry size changed while extracting" unless written == entry.size
            end
          end
          File.chmod(0o644, target)
        end

        def ensure_contained!(target, root)
          relative = target.cleanpath.relative_path_from(root.cleanpath)
          return unless relative.absolute? || relative.each_filename.first == ".."

          raise PackageError, "plugin package path escapes the staging directory"
        rescue ArgumentError
          raise PackageError, "plugin package path escapes the staging directory"
        end

        def secure_digest_match?(left, right)
          left.bytesize == right.bytesize &&
            left.bytes.zip(right.bytes).reduce(0) { |difference, (a, b)| difference | (a ^ b) }.zero?
        end
      end
    end
  end
end
