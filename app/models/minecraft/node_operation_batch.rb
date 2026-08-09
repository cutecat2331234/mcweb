# frozen_string_literal: true

module Minecraft
  class NodeOperationBatch < ApplicationRecord
    include HasPublicId

    alias_attribute :operation_id, :minecraft_node_operation_id
    alias_attribute :node_id, :minecraft_node_id

    ACTIVE_STATUSES = %w[dispatched running result_pending_ack].freeze
    TERMINAL_STATUSES = %w[completed completed_with_errors failed cancelled].freeze

    belongs_to :operation,
      class_name: "Minecraft::NodeOperation",
      foreign_key: :minecraft_node_operation_id,
      inverse_of: :batches
    belongs_to :node,
      class_name: "Minecraft::Node",
      foreign_key: :minecraft_node_id,
      inverse_of: :operation_batches
    has_many :target_results,
      class_name: "Minecraft::NodeOperationTargetResult",
      foreign_key: :minecraft_node_operation_batch_id,
      inverse_of: :batch,
      dependent: :restrict_with_error

    enum :status, {
      ready: "ready",
      dispatched: "dispatched",
      running: "running",
      result_pending_ack: "result_pending_ack",
      completed: "completed",
      completed_with_errors: "completed_with_errors",
      failed: "failed",
      cancelled: "cancelled"
    }, prefix: true, validate: true

    validates :delivery_id, :payload_digest, presence: true
    validates :delivery_id, uniqueness: true
    validates :acknowledgement_id, uniqueness: true, allow_nil: true

    scope :dispatchable, -> { where(status: :ready).order(:created_at) }
    scope :active, -> { where(status: ACTIVE_STATUSES) }
    scope :terminal, -> { where(status: TERMINAL_STATUSES) }

    def active?
      ACTIVE_STATUSES.include?(status)
    end

    def terminal?
      TERMINAL_STATUSES.include?(status)
    end
  end
end
