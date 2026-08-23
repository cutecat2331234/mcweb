# frozen_string_literal: true

module Minecraft
  class WorldRestorePlan < ApplicationRecord
    include HasPublicId

    self.table_name = "minecraft_world_restore_plans"

    ACTIVE_STATUSES = %w[planned authorized queued running recovery_required].freeze
    TERMINAL_STATUSES = %w[completed failed rolled_back expired cancelled].freeze
    SHA256_PATTERN = /\A[0-9a-f]{64}\z/
    FROZEN_FIELDS = %w[
      public_id minecraft_server_id minecraft_node_id minecraft_world_backup_id actor_id reason
      request_id request_digest plan_digest backup_manifest_digest server_configuration_digest
      node_capability_digest frozen_server_updated_at world_relative_path expires_at
    ].freeze
    EXECUTION_BINDING_FIELDS = %w[pre_restore_world_backup_id minecraft_node_operation_id].freeze
    STATUS_TRANSITIONS = {
      "planned" => %w[planned authorized expired cancelled],
      "authorized" => %w[authorized queued expired cancelled],
      "queued" => %w[queued running completed failed rolled_back recovery_required],
      "running" => %w[running completed failed rolled_back recovery_required],
      "completed" => %w[completed],
      "failed" => %w[failed],
      "rolled_back" => %w[rolled_back],
      "recovery_required" => %w[recovery_required],
      "expired" => %w[expired],
      "cancelled" => %w[cancelled]
    }.freeze

    belongs_to :server, class_name: "Minecraft::Server", foreign_key: :minecraft_server_id
    belongs_to :node, class_name: "Minecraft::Node", foreign_key: :minecraft_node_id
    belongs_to :world_backup,
      class_name: "Minecraft::WorldBackup",
      foreign_key: :minecraft_world_backup_id,
      inverse_of: :restore_plans
    belongs_to :pre_restore_world_backup,
      class_name: "Minecraft::WorldBackup",
      foreign_key: :pre_restore_world_backup_id,
      inverse_of: :pre_restore_plans,
      optional: true
    belongs_to :node_operation,
      class_name: "Minecraft::NodeOperation",
      foreign_key: :minecraft_node_operation_id,
      optional: true
    belongs_to :actor, class_name: "User"
    has_many :events,
      class_name: "Minecraft::WorldRestoreEvent",
      foreign_key: :minecraft_world_restore_plan_id,
      inverse_of: :restore_plan,
      dependent: :restrict_with_error

    enum :status, {
      planned: "planned",
      authorized: "authorized",
      queued: "queued",
      running: "running",
      completed: "completed",
      failed: "failed",
      rolled_back: "rolled_back",
      recovery_required: "recovery_required",
      expired: "expired",
      cancelled: "cancelled"
    }, prefix: true, validate: true

    validates :reason, presence: true, length: { maximum: 1_000 }
    validates :request_id,
      format: { with: /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/ },
      uniqueness: true
    validates :request_digest, :plan_digest, :backup_manifest_digest,
      :server_configuration_digest, :node_capability_digest,
      format: { with: SHA256_PATTERN }
    validates :authorization_digest, format: { with: SHA256_PATTERN }, allow_nil: true
    validates :world_relative_path, presence: true, length: { maximum: 1_024 }
    validate :frozen_contract_is_immutable, on: :update
    validate :execution_binding_is_immutable, on: :update
    validate :status_transition_is_valid, on: :update

    scope :recent, -> { order(created_at: :desc) }
    scope :active, -> {
      where(status: ACTIVE_STATUSES).where(
        "status NOT IN ('planned', 'authorized') OR expires_at > ?",
        Time.current
      )
    }
    scope :blocking_server_start, -> { active }

    def active?
      return false unless ACTIVE_STATUSES.include?(status)
      return true unless status.in?(%w[planned authorized])

      expires_at.present? && expires_at > Time.current
    end

    def terminal?
      TERMINAL_STATUSES.include?(status)
    end

    private

    def frozen_contract_is_immutable
      return if (changes_to_save.keys & FROZEN_FIELDS).empty?

      errors.add(:base, :immutable)
    end

    def execution_binding_is_immutable
      changed_binding = EXECUTION_BINDING_FIELDS.any? do |field|
        public_send("#{field}_in_database").present? && public_send("will_save_change_to_#{field}?")
      end
      errors.add(:base, :immutable) if changed_binding
    end

    def status_transition_is_valid
      previous = status_in_database
      return if previous.blank? || STATUS_TRANSITIONS.fetch(previous, []).include?(status)

      errors.add(:status, :invalid_transition)
    end
  end
end
