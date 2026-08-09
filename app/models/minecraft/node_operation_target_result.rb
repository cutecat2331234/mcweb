# frozen_string_literal: true

module Minecraft
  class NodeOperationTargetResult < ApplicationRecord
    belongs_to :batch,
      class_name: "Minecraft::NodeOperationBatch",
      foreign_key: :minecraft_node_operation_batch_id,
      inverse_of: :target_results
    belongs_to :server,
      class_name: "Minecraft::Server",
      foreign_key: :minecraft_server_id,
      optional: true

    enum :status, {
      completed: "completed",
      failed: "failed"
    }, prefix: true, validate: true

    validates :target_key, presence: true, uniqueness: { scope: :minecraft_node_operation_batch_id }
  end
end
