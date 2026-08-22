# frozen_string_literal: true

require "digest"
require "fileutils"
require "find"
require "json"
require "pathname"
require "time"

require_relative "object_archive"

module Mcweb
  module DisasterRecovery
    class BackupRetention
      BACKUP_ID_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/
      CHECKSUM_PATTERN = /\A([0-9a-f]{64}) [ *]([A-Za-z0-9._\/-]+)\z/
      FORBIDDEN_ROOTS = %w[/ /etc /opt /usr /var /var/backups].freeze

      Candidate = Data.define(:backup_id, :path, :created_at, :manifest)

      class Error < StandardError
        attr_reader :code

        def initialize(code)
          @code = code
          super(code)
        end
      end

      def initialize(root:, retention_days:, retention_count:, now: Time.now.utc)
        @root = validate_root!(root)
        @retention_days = bounded_integer(retention_days, 1..3650, "backup_retention_days_invalid")
        @retention_count = bounded_integer(retention_count, 1..1000, "backup_retention_count_invalid")
        @now = now
      end

      def prune!
        resume_interrupted_prunes!
        candidates = complete_candidates.sort_by(&:created_at).reverse
        protected_ids = candidates.first(@retention_count).map(&:backup_id)
        threshold = @now - (@retention_days * 86_400)
        expired = candidates.reject { |candidate| protected_ids.include?(candidate.backup_id) }
          .select { |candidate| candidate.created_at <= threshold }

        expired.each { |candidate| prune_candidate!(candidate) }
        expired.map(&:backup_id)
      end

      private

      def validate_root!(root)
        value = root.to_s
        raise Error, "backup_root_invalid" unless Pathname.new(value).absolute?
        raise Error, "backup_root_invalid" if File.symlink?(value) || !File.directory?(value)

        canonical = File.realpath(value)
        raise Error, "backup_root_not_canonical" unless File.expand_path(value) == canonical
        raise Error, "backup_root_too_broad" if FORBIDDEN_ROOTS.include?(canonical)

        canonical
      rescue Errno::ENOENT, Errno::EACCES
        raise Error, "backup_root_unreadable"
      end

      def bounded_integer(value, range, code)
        parsed = Integer(value, 10)
        raise Error, code unless range.cover?(parsed)

        parsed
      rescue ArgumentError, TypeError
        raise Error, code
      end

      def complete_candidates
        Dir.children(@root).filter_map do |name|
          next unless name.match?(BACKUP_ID_PATTERN)

          path = File.join(@root, name)
          next unless File.directory?(path) && !File.symlink?(path)
          next unless File.file?(File.join(path, "backup-manifest.json")) &&
            File.file?(File.join(path, "SHA256SUMS"))

          load_candidate(path, expected_id: name)
        end
      rescue Errno::EACCES
        raise Error, "backup_root_unreadable"
      end

      def resume_interrupted_prunes!
        Dir.children(@root).grep(/\A\.pruning-[A-Za-z0-9][A-Za-z0-9._-]*\z/).sort.each do |name|
          path = File.join(@root, name)
          raise Error, "backup_prune_stage_invalid" if File.symlink?(path) || !File.directory?(path)

          candidate = load_candidate(path)
          unless name == ".pruning-#{candidate.backup_id}"
            raise Error, "backup_prune_stage_invalid"
          end
          prune_staged_candidate!(candidate)
        end
      end

      def load_candidate(path, expected_id: nil)
        manifest_path = File.join(path, "backup-manifest.json")
        checksums_path = File.join(path, "SHA256SUMS")
        raise Error, "backup_generation_incomplete" unless File.file?(manifest_path) && File.file?(checksums_path)
        raise Error, "backup_generation_unsafe" if tree_contains_unsafe_entry?(path)

        manifest = JSON.parse(File.binread(manifest_path))
        backup_id = manifest["backup_id"]
        format = manifest["format"]
        unless backup_id.is_a?(String) && backup_id.match?(BACKUP_ID_PATTERN) &&
            (expected_id.nil? || backup_id == expected_id) && format == "mcweb-backup-v2"
          raise Error, "backup_generation_manifest_invalid"
        end
        validate_storage_manifest!(manifest["active_storage"])
        created_at = Time.iso8601(manifest.fetch("created_at")).utc
        raise Error, "backup_generation_time_invalid" if created_at > @now + 300

        validate_checksum_coverage!(path, checksums_path)
        Candidate.new(backup_id:, path:, created_at:, manifest:)
      rescue JSON::ParserError, KeyError, ArgumentError
        raise Error, "backup_generation_manifest_invalid"
      end

      def validate_checksum_coverage!(path, checksums_path)
        listed = {}
        File.foreach(checksums_path, chomp: true) do |line|
          match = CHECKSUM_PATTERN.match(line)
          raise Error, "backup_generation_checksums_invalid" unless match

          expected, relative = match.captures
          validate_relative_path!(relative)
          raise Error, "backup_generation_checksums_invalid" if listed.key?(relative)

          artifact = File.join(path, relative)
          unless File.file?(artifact) && !File.symlink?(artifact) &&
              Digest::SHA256.file(artifact).hexdigest == expected
            raise Error, "backup_generation_integrity_failed"
          end
          listed[relative] = true
        end

        discovered = Dir.glob("**/*", File::FNM_DOTMATCH, base: path)
          .select { |relative| File.file?(File.join(path, relative)) }
          .reject { |relative| relative == "SHA256SUMS" }
        unless discovered.sort == listed.keys.sort
          raise Error, "backup_generation_checksums_incomplete"
        end
      rescue Errno::ENOENT, Errno::EACCES
        raise Error, "backup_generation_unreadable"
      end

      def validate_storage_manifest!(storage)
        raise Error, "backup_generation_manifest_invalid" unless storage.is_a?(Hash)

        case storage["mode"]
        when "local"
          valid = storage["inventory"] == "active_storage_files.sha256" &&
            storage["archive"] == "active_storage.tar.gz" && storage["remote_snapshot"].nil?
        when "private_s3"
          snapshot = storage["remote_snapshot"]
          valid = storage["inventory"] == "active_storage_objects.ndjson" &&
            storage["archive"].nil? && snapshot.is_a?(Hash) &&
            snapshot["provider"] == "s3" &&
            snapshot["inventory_format"] == ObjectArchive::INVENTORY_FORMAT &&
            valid_bucket?(snapshot["source_bucket"]) &&
            valid_bucket?(snapshot["backup_bucket"]) &&
            snapshot["source_bucket"] != snapshot["backup_bucket"]
        else
          valid = false
        end
        raise Error, "backup_generation_manifest_invalid" unless valid
      end

      def valid_bucket?(value)
        value.is_a?(String) && value.bytesize.between?(1, 255) &&
          value.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]*\z/)
      end

      def validate_relative_path!(relative)
        segments = relative.split("/")
        valid = !relative.start_with?("/") && segments.none? do |segment|
          segment.empty? || [ ".", ".." ].include?(segment)
        end
        raise Error, "backup_generation_checksums_invalid" unless valid
      end

      def tree_contains_unsafe_entry?(path)
        root_device = File.stat(path).dev
        Find.find(path).any? do |entry|
          stat = File.lstat(entry)
          stat.dev != root_device || (!stat.file? && !stat.directory?)
        end
      rescue Errno::EACCES, Errno::ENOENT
        true
      end

      def prune_candidate!(candidate)
        staged = File.join(@root, ".pruning-#{candidate.backup_id}")
        raise Error, "backup_prune_stage_exists" if File.exist?(staged) || File.symlink?(staged)

        File.rename(candidate.path, staged)
        prune_staged_candidate!(
          Candidate.new(
            backup_id: candidate.backup_id,
            path: staged,
            created_at: candidate.created_at,
            manifest: candidate.manifest
          )
        )
      rescue Errno::EACCES, Errno::ENOTEMPTY
        raise Error, "backup_prune_stage_failed"
      end

      def prune_staged_candidate!(candidate)
        storage = candidate.manifest.fetch("active_storage")
        if storage["mode"] == "private_s3"
          inventory_name = storage["inventory"]
          raise Error, "backup_generation_manifest_invalid" unless inventory_name == "active_storage_objects.ndjson"

          inventory = ObjectArchive::Inventory.load(File.join(candidate.path, inventory_name))
          store = ObjectArchive::Store.from_environment("MCWEB_BACKUP_S3")
          backup_prefix = ENV.fetch("MCWEB_BACKUP_S3_PREFIX", "mcweb-backups")
          expected_prefix = "#{backup_prefix}/#{candidate.backup_id}/objects"
          validate_snapshot_prefix!(expected_prefix)
          ObjectArchive.new(backup_store: store).prune(inventory, expected_prefix:)
        end

        ensure_staged_path!(candidate.path)
        FileUtils.remove_entry_secure(candidate.path)
      rescue KeyError
        raise Error, "backup_generation_manifest_invalid"
      end

      def ensure_staged_path!(path)
        parent = File.realpath(File.dirname(path))
        name = File.basename(path)
        unless parent == @root && name.match?(/\A\.pruning-[A-Za-z0-9][A-Za-z0-9._-]*\z/) &&
            File.directory?(path) && !File.symlink?(path)
          raise Error, "backup_prune_stage_invalid"
        end
      end

      def validate_snapshot_prefix!(prefix)
        segments = prefix.split("/")
        valid = prefix.bytesize.between?(1, 1024) && prefix.match?(ObjectArchive::KEY_PATTERN) &&
          segments.none? { |segment| segment.empty? || [ ".", ".." ].include?(segment) }
        raise Error, "snapshot_prune_scope_invalid" unless valid
      end
    end
  end
end
