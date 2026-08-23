# frozen_string_literal: true

module Minecraft
  class WorldRestoreResolution < ApplicationRecord
    include HasPublicId

    self.table_name = "minecraft_world_restore_resolutions"

    ACTIONS = %w[resume rollback reconcile].freeze
    ACTIVE_STATUSES = %w[planned authorized queued running].freeze
    TERMINAL_STATUSES = %w[completed failed recovery_required expired cancelled taken_over].freeze
    SHA256_PATTERN = /\A[0-9a-f]{64}\z/
    FROZEN_FIELDS = %w[
      public_id minecraft_world_restore_plan_id actor_id resolution_action reason request_id
      request_digest expected_plan_lock_version plan_digest server_configuration_digest
      node_capability_digest pre_restore_manifest_digest expires_at supersedes_resolution_id
    ].freeze
    LIFECYCLE_FIELDS = %w[
      expired_at lifecycle_action lifecycle_actor_id lifecycle_reason lifecycle_request_id
      lifecycle_request_digest lifecycle_authorization_method lifecycle_authorized_at
      lifecycle_completed_at
    ].freeze
    AUTHORIZATION_FIELDS = %w[
      authorization_digest authorization_method authorization_expires_at authorized_at
      authorization_consumed_at
    ].freeze
    TERMINAL_EVIDENCE_FIELDS = %w[
      result_summary error_code started_at completed_at queued_at minecraft_node_operation_id
    ].freeze
    STATUS_TRANSITIONS = {
      "planned" => %w[planned authorized failed expired cancelled taken_over],
      "authorized" => %w[authorized queued failed expired cancelled taken_over],
      "queued" => %w[queued running completed failed recovery_required],
      "running" => %w[running completed failed recovery_required],
      "completed" => %w[completed],
      "failed" => %w[failed],
      "recovery_required" => %w[recovery_required],
      "expired" => %w[expired],
      "cancelled" => %w[cancelled],
      "taken_over" => %w[taken_over]
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
    belongs_to :lifecycle_actor, class_name: "User", optional: true
    belongs_to :superseded_resolution,
      class_name: "Minecraft::WorldRestoreResolution",
      foreign_key: :supersedes_resolution_id,
      inverse_of: :superseding_resolution,
      optional: true
    has_one :superseding_resolution,
      class_name: "Minecraft::WorldRestoreResolution",
      foreign_key: :supersedes_resolution_id,
      inverse_of: :superseded_resolution,
      dependent: :restrict_with_error

    enum :status, {
      planned: "planned",
      authorized: "authorized",
      queued: "queued",
      running: "running",
      completed: "completed",
      failed: "failed",
      recovery_required: "recovery_required",
      expired: "expired",
      cancelled: "cancelled",
      taken_over: "taken_over"
    }, prefix: true, validate: true

    enum :resolution_action, {
      resume: "resume",
      rollback: "rollback",
      reconcile: "reconcile"
    }, prefix: true, validate: true

    validates :reason, presence: true, length: { maximum: 1_000 }
    validates :expires_at, presence: true
    validates :request_id,
      format: { with: /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/ },
      uniqueness: true
    validates :expected_plan_lock_version, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :request_digest, :plan_digest, :server_configuration_digest, :node_capability_digest,
      format: { with: SHA256_PATTERN }
    validates :pre_restore_manifest_digest, :authorization_digest,
      format: { with: SHA256_PATTERN },
      allow_nil: true
    validates :lifecycle_request_digest, format: { with: SHA256_PATTERN }, allow_nil: true
    validates :lifecycle_request_id,
      format: { with: /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/ },
      allow_nil: true
    validates :lifecycle_action, inclusion: { in: %w[cancel takeover] }, allow_nil: true
    validates :lifecycle_authorization_method,
      inclusion: { in: %w[password totp recovery_code] },
      allow_nil: true
    validates :lifecycle_reason, length: { maximum: 1_000 }, allow_nil: true
    validate :frozen_contract_is_immutable, on: :update
    validate :lifecycle_contract_is_immutable, on: :update
    validate :terminal_contract_is_immutable, on: :update
    validate :operation_binding_is_immutable, on: :update
    validate :status_transition_is_valid, on: :update
    validate :lifecycle_contract_matches_status
    validate :superseded_resolution_matches_plan

    scope :recent, -> { order(created_at: :desc) }
    scope :active, -> { where(status: ACTIVE_STATUSES) }
    scope :expirable, -> { where(status: %w[planned authorized]) }

    def terminal?
      TERMINAL_STATUSES.include?(status)
    end

    def expired_by_time?(at = Time.current)
      status.in?(%w[planned authorized]) && expires_at <= at
    end

    private

    def frozen_contract_is_immutable
      errors.add(:base, :immutable) if (changes_to_save.keys & FROZEN_FIELDS).any?
    end

    def lifecycle_contract_is_immutable
      changed = changes_to_save.keys & LIFECYCLE_FIELDS
      return if changed.empty?

      errors.add(:base, :immutable) if changed.any? { |field| attribute_in_database(field).present? }
    end

    def terminal_contract_is_immutable
      previous = status_in_database
      if (TERMINAL_STATUSES.include?(previous) || TERMINAL_STATUSES.include?(status)) &&
          (changes_to_save.keys & AUTHORIZATION_FIELDS).any?
        errors.add(:base, :immutable)
      end
      if TERMINAL_STATUSES.include?(previous) &&
          (changes_to_save.keys & TERMINAL_EVIDENCE_FIELDS).any?
        errors.add(:base, :immutable)
      end
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

    def lifecycle_contract_matches_status
      fields = LIFECYCLE_FIELDS.index_with { |field| public_send(field) }
      if status_expired?
        errors.add(:expired_at, :blank) if expired_at.blank?
        errors.add(:base, :invalid) if fields.except("expired_at").values.any?(&:present?)
      elsif status_cancelled? || status_taken_over?
        expected_action = status_cancelled? ? "cancel" : "takeover"
        errors.add(:lifecycle_action, :invalid) unless lifecycle_action == expected_action
        %w[
          lifecycle_actor_id lifecycle_reason lifecycle_request_id lifecycle_request_digest
          lifecycle_authorization_method lifecycle_authorized_at lifecycle_completed_at
        ].each { |field| errors.add(field, :blank) if public_send(field).blank? }
        errors.add(:expired_at, :invalid) if expired_at.present?
      elsif fields.values.any?(&:present?)
        errors.add(:base, :invalid)
      end
    end

    def superseded_resolution_matches_plan
      return unless superseded_resolution
      return if superseded_resolution.minecraft_world_restore_plan_id == minecraft_world_restore_plan_id

      errors.add(:superseded_resolution, :invalid)
    end
  end
end
