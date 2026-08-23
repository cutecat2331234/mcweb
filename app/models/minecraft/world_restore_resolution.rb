# frozen_string_literal: true

module Minecraft
  class WorldRestoreResolution < ApplicationRecord
    include HasPublicId

    self.table_name = "minecraft_world_restore_resolutions"

    ACTIONS = %w[resume rollback reconcile].freeze
    ACTIVE_STATUSES = %w[planned authorized queued running].freeze
    TERMINAL_STATUSES = %w[completed failed recovery_required].freeze
    SHA256_PATTERN = /\A[0-9a-f]{64}\z/
    FROZEN_FIELDS = %w[
      public_id minecraft_world_restore_plan_id actor_id resolution_action reason request_id
      request_digest expected_plan_lock_version plan_digest server_configuration_digest
      node_capability_digest pre_restore_manifest_digest
    ].freeze
    STATUS_TRANSITIONS = {
      "planned" => %w[planned authorized failed],
      "authorized" => %w[authorized queued failed],
      "queued" => %w[queued running completed failed recovery_required],
      "running" => %w[running completed failed recovery_required],
      "completed" => %w[completed],
      "failed" => %w[failed],
      "recovery_required" => %w[recovery_required]
    }.freeze

    belongs_to :restore_plan,
      class_name: "Minecraft::WorldRestorePlan",
      foreign_key: :minecraft_world_restore_plan_id,
      inverse_of: :recovery_resolutions
    belongs_to :node_operation,
      class_name: "Minecraft::NodeOperation",
      foreign_key: :minecraft_node_operation_id,
      inverse_of: :world_restore_resolution,
      optional: true
    belongs_to :actor, class_name: "User"

    enum :status, {
      planned: "planned",
      authorized: "authorized",
      queued: "queued",
      running: "running",
      completed: "completed",
      failed: "failed",
      recovery_required: "recovery_required"
    }, prefix: true, validate: true

    enum :resolution_action, {
      resume: "resume",
      rollback: "rollback",
      reconcile: "reconcile"
    }, prefix: true, validate: true

    validates :reason, presence: true, length: { maximum: 1_000 }
    validates :request_id,
      format: { with: /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/ },
      uniqueness: true
    validates :expected_plan_lock_version, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :request_digest, :plan_digest, :server_configuration_digest, :node_capability_digest,
      format: { with: SHA256_PATTERN }
    validates :pre_restore_manifest_digest, :authorization_digest,
      format: { with: SHA256_PATTERN },
      allow_nil: true
    validate :frozen_contract_is_immutable, on: :update
    validate :operation_binding_is_immutable, on: :update
    validate :status_transition_is_valid, on: :update

    scope :recent, -> { order(created_at: :desc) }
    scope :active, -> { where(status: ACTIVE_STATUSES) }

    def terminal?
      TERMINAL_STATUSES.include?(status)
    end

    private

    def frozen_contract_is_immutable
      errors.add(:base, :immutable) if (changes_to_save.keys & FROZEN_FIELDS).any?
    end

    def operation_binding_is_immutable
      return unless minecraft_node_operation_id_in_database.present? &&
        will_save_change_to_minecraft_node_operation_id?

      errors.add(:base, :immutable)
    end

    def status_transition_is_valid
      previous = status_in_database
      return if previous.blank? || STATUS_TRANSITIONS.fetch(previous, []).include?(status)

      errors.add(:status, :invalid_transition)
    end
  end
end
