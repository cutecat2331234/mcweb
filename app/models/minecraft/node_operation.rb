# frozen_string_literal: true

module Minecraft
  class NodeOperation < ApplicationRecord
    include HasPublicId

    has_many :batches,
      class_name: "Minecraft::NodeOperationBatch",
      foreign_key: :minecraft_node_operation_id,
      inverse_of: :operation,
      dependent: :restrict_with_error
    has_many :target_results,
      through: :batches,
      source: :target_results
    has_one :world_backup,
      class_name: "Minecraft::WorldBackup",
      foreign_key: :minecraft_node_operation_id,
      inverse_of: :node_operation,
      dependent: :restrict_with_error
    has_one :world_restore_plan,
      class_name: "Minecraft::WorldRestorePlan",
      foreign_key: :minecraft_node_operation_id,
      inverse_of: :node_operation,
      dependent: :restrict_with_error

    enum :status, {
      queued: "queued",
      preparing: "preparing",
      ready: "ready",
      running: "running",
      completed: "completed",
      completed_with_errors: "completed_with_errors",
      failed: "failed",
      cancelled: "cancelled"
    }, prefix: true, validate: true

    validates :operation_type, :request_digest, presence: true
    validates :idempotency_key, uniqueness: true, allow_nil: true
    validates :dispatch_slot, inclusion: { in: [ 1 ] }, allow_nil: true

    scope :active, -> { where(status: %w[queued preparing ready running]) }
    scope :dispatching, -> { where(status: %w[preparing ready running]) }

    def terminal?
      status_completed? || status_completed_with_errors? || status_failed? || status_cancelled?
    end
  end
end
