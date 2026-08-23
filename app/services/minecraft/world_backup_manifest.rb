# frozen_string_literal: true

module Minecraft
  class WorldBackupManifest
    MANIFEST_VERSION = 1
    SAFETY_PROFILE = "mcweb-world-restore-v1"
    ARCHIVE_FORMAT = "tar.gz"
    SHA256_PATTERN = /\A[0-9a-f]{64}\z/
    MAX_ENTRY_COUNT = 2_000_000
    MAX_ARCHIVE_BYTES = 64.gigabytes
    MAX_UNCOMPRESSED_BYTES = 256.gigabytes

    class << self
      def normalize(value, backup:)
        manifest = value.to_h.deep_stringify_keys
        required = %w[
          manifest_version safety_profile backup_id server_id node_id purpose request_digest created_at archive_format
          archive_sha256 manifest_digest archive_bytes uncompressed_bytes entry_count world_relative_path
          source_process_state source_world_state
        ]
        return failure(:world_backup_manifest_invalid) unless required.all? { |key| manifest[key].present? }
        return failure(:world_backup_manifest_invalid) unless manifest["manifest_version"].to_i == MANIFEST_VERSION
        return failure(:world_backup_manifest_invalid) unless manifest["safety_profile"] == SAFETY_PROFILE
        return failure(:world_backup_manifest_invalid) unless manifest["archive_format"] == ARCHIVE_FORMAT
        return failure(:world_backup_manifest_invalid) unless manifest["backup_id"] == backup.public_id
        return failure(:world_backup_manifest_invalid) unless manifest["server_id"] == backup.server.public_id
        return failure(:world_backup_manifest_invalid) unless manifest["node_id"] == backup.node.public_id
        return failure(:world_backup_manifest_invalid) unless manifest["purpose"] == backup.purpose
        return failure(:world_backup_manifest_invalid) unless manifest["request_digest"] == backup.request_digest
        return failure(:world_backup_manifest_invalid) unless manifest["archive_sha256"].to_s.match?(SHA256_PATTERN)
        return failure(:world_backup_manifest_invalid) unless manifest["manifest_digest"].to_s.match?(SHA256_PATTERN)

        path_result = Minecraft::WorldPathPolicy.call(manifest["world_relative_path"])
        return path_result if path_result.failure?

        archive_bytes = bounded_integer(manifest["archive_bytes"], MAX_ARCHIVE_BYTES)
        uncompressed_bytes = bounded_integer(manifest["uncompressed_bytes"], MAX_UNCOMPRESSED_BYTES)
        entry_count = bounded_integer(manifest["entry_count"], MAX_ENTRY_COUNT)
        return failure(:world_backup_manifest_invalid) unless
          archive_bytes&.positive? && uncompressed_bytes && entry_count

        created_at = Time.iso8601(manifest["created_at"].to_s)
        return failure(:world_backup_manifest_invalid) if created_at > 5.minutes.from_now
        source_state = manifest["source_process_state"].to_s
        world_state = manifest["source_world_state"].to_s
        return failure(:world_backup_manifest_invalid) unless
          source_state == "stopped" && world_state.in?(%w[present absent])

        summary = {
          "manifest_version" => MANIFEST_VERSION,
          "safety_profile" => SAFETY_PROFILE,
          "backup_id" => backup.public_id,
          "server_id" => backup.server.public_id,
          "node_id" => backup.node.public_id,
          "purpose" => backup.purpose,
          "created_at" => created_at.utc.iso8601(6),
          "archive_format" => ARCHIVE_FORMAT,
          "archive_sha256" => manifest["archive_sha256"].downcase,
          "manifest_digest" => manifest["manifest_digest"].downcase,
          "archive_bytes" => archive_bytes,
          "uncompressed_bytes" => uncompressed_bytes,
          "entry_count" => entry_count,
          "world_relative_path" => path_result.value.fetch(:path),
          "source_process_state" => source_state.presence,
          "source_world_state" => world_state.presence
        }.compact

        ServiceResult.success(summary: summary)
      rescue ArgumentError, TypeError
        failure(:world_backup_manifest_invalid)
      end

      private

      def bounded_integer(value, maximum)
        integer = Integer(value)
        integer if integer.between?(0, maximum)
      rescue ArgumentError, TypeError
        nil
      end

      def failure(code)
        ServiceResult.failure(error: code, code: code)
      end
    end
  end
end
