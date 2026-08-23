# frozen_string_literal: true

module Minecraft
  class Node < ApplicationRecord
    include HasPublicId

    WORLD_CAPABILITY_COMMON_KEYS = %w[
      protocol_version manifest_versions archive_formats safety_profile
    ].freeze
    WORLD_RESTORE_LIMIT_MAXIMUMS = {
      "max_archive_bytes" => 64.gigabytes,
      "max_manifest_bytes" => 256.megabytes,
      "max_uncompressed_bytes" => 256.gigabytes,
      "max_file_bytes" => 64.gigabytes,
      "max_entries" => 2_000_000,
      "max_directories" => 1_000_000,
      "max_depth" => 64,
      "max_path_bytes" => 1_024,
      "max_expansion_ratio" => 200
    }.freeze

    has_encrypted :node_secret, encrypted_attribute: :encrypted_node_secret

    has_many :servers, class_name: "Minecraft::Server", foreign_key: :minecraft_node_id, dependent: :nullify
    has_many :node_tasks, class_name: "Minecraft::NodeTask", foreign_key: :minecraft_node_id, dependent: :destroy
    has_many :operation_batches,
      class_name: "Minecraft::NodeOperationBatch",
      foreign_key: :minecraft_node_id,
      inverse_of: :node,
      dependent: :restrict_with_error
    has_many :world_backups,
      class_name: "Minecraft::WorldBackup",
      foreign_key: :minecraft_node_id,
      inverse_of: :node,
      dependent: :restrict_with_error
    has_many :world_restore_plans,
      class_name: "Minecraft::WorldRestorePlan",
      foreign_key: :minecraft_node_id,
      inverse_of: :node,
      dependent: :restrict_with_error
    has_many :metric_snapshots, class_name: "Minecraft::NodeMetricSnapshot", foreign_key: :minecraft_node_id, dependent: :destroy

    enum :status, { offline: "offline", online: "online", maintenance: "maintenance" }, validate: true

    validates :name, presence: true

    def wake_for_tasks!
      update!(tasks_wake_at: Time.current)
    end

    def heartbeat!
      update!(last_heartbeat_at: Time.current, status: :online)
    end

    def generate_node_secret!
      secret = SecureRandom.hex(32)
      self.node_secret = secret
      self.node_secret_fingerprint = Digest::SHA256.hexdigest(secret)[0, 16]
      save!
      secret
    end

    def verify_node_secret(secret)
      node_secret.present? && node_secret == secret
    end

    def effective_proxy_listen_url
      proxy_listen_url.presence || "http://127.0.0.1:9876"
    end

    def supports_operation_batches?
      Array(metadata["node_protocol_versions"]).map(&:to_i).include?(2)
    end

    def supports_node_operation?(operation_type)
      supports_operation_batches? &&
        Array(metadata["operation_types"]).map(&:to_s).include?(operation_type.to_s)
    end

    def fresh_heartbeat?(at: Time.current, maximum_age: 3.minutes)
      status_online? && last_heartbeat_at.present? && last_heartbeat_at >= at - maximum_age
    end

    def supports_managed_world_backups_v2?
      world_capability_valid?("world_backup_create", required_flags: %w[stopped_source_required managed_storage])
    end

    def supports_world_restore_v2?
      world_capability_valid?(
        "world_restore_execute",
        required_flags: %w[
          safe_extract same_filesystem_atomic_swap pre_restore_snapshot durable_ledger crash_recovery rollback
        ]
      )
    end

    def world_safety_capability_snapshot
      raw_capabilities = metadata["operation_capabilities"]
      capabilities = raw_capabilities.is_a?(Hash) ? raw_capabilities : {}
      {
        "node_protocol_versions" => Array(metadata["node_protocol_versions"]).map(&:to_i).sort,
        "operation_types" => Array(metadata["operation_types"]).map(&:to_s).sort,
        "world_backup_create" => normalized_capability(capabilities["world_backup_create"]),
        "world_restore_execute" => normalized_capability(capabilities["world_restore_execute"]),
        "world_restore_recovery_required" => ActiveModel::Type::Boolean.new.cast(
          metadata["world_restore_recovery_required"]
        )
      }
    end

    def world_safety_capability_digest
      Minecraft::NodeOperationDigest.call(world_safety_capability_snapshot)
    end

    private

    def world_capability_valid?(operation_type, required_flags:)
      return false unless supports_node_operation?(operation_type)

      capability = normalized_capability(metadata.dig("operation_capabilities", operation_type))
      return false if capability.empty?
      expected_keys = WORLD_CAPABILITY_COMMON_KEYS + required_flags
      expected_keys += [ "local_limits" ] if operation_type == "world_restore_execute"
      return false unless capability.keys.sort == expected_keys.sort
      return false unless capability["protocol_version"].to_i == 2
      return false unless Array(capability["manifest_versions"]).map(&:to_i) == [ 1 ]
      return false unless Array(capability["archive_formats"]).map(&:to_s) == [ "tar.gz" ]
      return false unless capability["safety_profile"] == Minecraft::WorldBackupManifest::SAFETY_PROFILE
      return false if operation_type == "world_restore_execute" && !world_restore_limits_valid?(
        capability["local_limits"]
      )

      required_flags.all? { |flag| capability[flag] == true }
    end

    def world_restore_limits_valid?(value)
      limits = normalized_capability(value)
      return false unless limits.keys.sort == WORLD_RESTORE_LIMIT_MAXIMUMS.keys.sort

      WORLD_RESTORE_LIMIT_MAXIMUMS.all? do |key, maximum|
        configured = limits[key]
        configured.is_a?(Numeric) && configured.positive? && configured <= maximum &&
          (key == "max_expansion_ratio" || configured.to_i == configured)
      end
    end

    def normalized_capability(value)
      value.is_a?(Hash) ? value.deep_stringify_keys : {}
    end
  end
end
