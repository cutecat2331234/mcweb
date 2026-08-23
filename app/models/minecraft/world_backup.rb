# frozen_string_literal: true

module Minecraft
  class WorldBackup < ApplicationRecord
    include HasPublicId

    self.table_name = "minecraft_world_backups"

    PURPOSES = %w[manual scheduled pre_restore].freeze
    STATUSES = %w[requested queued creating available failed quarantined].freeze
    SHA256_PATTERN = /\A[0-9a-f]{64}\z/
    IMMUTABLE_IDENTITY_FIELDS = %w[
      public_id minecraft_server_id minecraft_node_id created_by_id purpose request_id request_digest
    ].freeze
    IMMUTABLE_MANIFEST_FIELDS = %w[
      manifest_version safety_profile archive_format manifest_digest archive_sha256
      archive_bytes uncompressed_bytes entry_count manifest_summary
    ].freeze
    STATUS_TRANSITIONS = {
      "requested" => %w[requested queued failed],
      "queued" => %w[queued creating available failed],
      "creating" => %w[creating available failed],
      "available" => %w[available quarantined],
      "failed" => %w[failed],
      "quarantined" => %w[quarantined]
    }.freeze

    belongs_to :server, class_name: "Minecraft::Server", foreign_key: :minecraft_server_id
    belongs_to :node, class_name: "Minecraft::Node", foreign_key: :minecraft_node_id
    belongs_to :node_operation,
      class_name: "Minecraft::NodeOperation",
      foreign_key: :minecraft_node_operation_id,
      optional: true
    belongs_to :created_by, class_name: "User", optional: true

    has_many :restore_plans,
      class_name: "Minecraft::WorldRestorePlan",
      foreign_key: :minecraft_world_backup_id,
      inverse_of: :world_backup,
      dependent: :restrict_with_error
    has_many :pre_restore_plans,
      class_name: "Minecraft::WorldRestorePlan",
      foreign_key: :pre_restore_world_backup_id,
      inverse_of: :pre_restore_world_backup,
      dependent: :restrict_with_error

    enum :purpose, PURPOSES.index_with(&:itself), prefix: true, validate: true
    enum :status, STATUSES.index_with(&:itself), prefix: true, validate: true

    validates :request_id,
      format: { with: /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/ },
      uniqueness: true
    validates :request_digest, format: { with: SHA256_PATTERN }
    validates :manifest_digest, :archive_sha256, format: { with: SHA256_PATTERN }, allow_nil: true
    validates :archive_bytes, :uncompressed_bytes, :entry_count,
      numericality: { only_integer: true, greater_than_or_equal_to: 0 },
      allow_nil: true
    validate :identity_is_immutable, on: :update
    validate :operation_binding_is_immutable, on: :update
    validate :verified_manifest_is_immutable, on: :update
    validate :status_transition_is_valid, on: :update

    scope :recent, -> { order(created_at: :desc) }
    scope :restorable, -> { where(status: :available) }

    def restorable?
      summary = manifest_summary.to_h
      status_available? &&
        manifest_version == Minecraft::WorldBackupManifest::MANIFEST_VERSION &&
        safety_profile == Minecraft::WorldBackupManifest::SAFETY_PROFILE &&
        archive_format == Minecraft::WorldBackupManifest::ARCHIVE_FORMAT &&
        manifest_digest.to_s.match?(SHA256_PATTERN) &&
        archive_sha256.to_s.match?(SHA256_PATTERN) &&
        archive_bytes.to_i.positive? && !uncompressed_bytes.nil? && !entry_count.nil? &&
        summary["world_relative_path"].present? &&
        summary["source_process_state"] == "stopped" &&
        summary["source_world_state"].in?(%w[present absent])
    end

    private

    def identity_is_immutable
      return if (changes_to_save.keys & IMMUTABLE_IDENTITY_FIELDS).empty?

      errors.add(:base, :immutable)
    end

    def verified_manifest_is_immutable
      return unless status_in_database.in?(%w[available quarantined])
      return if (changes_to_save.keys & IMMUTABLE_MANIFEST_FIELDS).empty?

      errors.add(:base, :immutable)
    end

    def operation_binding_is_immutable
      return if minecraft_node_operation_id_in_database.nil?
      return unless will_save_change_to_minecraft_node_operation_id?

      errors.add(:minecraft_node_operation_id, :immutable)
    end

    def status_transition_is_valid
      previous = status_in_database
      return if previous.blank? || STATUS_TRANSITIONS.fetch(previous, []).include?(status)

      errors.add(:status, :invalid_transition)
    end
  end
end
