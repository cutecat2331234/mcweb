# frozen_string_literal: true

module Minecraft
  class PrepareNodeOperationJob < ApplicationJob
    queue_as :minecraft

    def perform
      nodes_to_wake = []

      Minecraft::NodeOperation.transaction do
        return if Minecraft::NodeOperation.dispatching.exists?

        operation = Minecraft::NodeOperation
          .where(status: :queued)
          .order(:created_at, :id)
          .lock
          .first
        return unless operation

        operation.update!(status: "preparing", dispatch_slot: 1)
        targets_by_node = operation.request_payload.fetch("targets").group_by { |target| target.fetch("node_id") }

        targets_by_node.each do |node_public_id, targets|
          node = Minecraft::Node.find_by!(public_id: node_public_id)
          payload = {
            "protocol_version" => 2,
            "operation_id" => operation.public_id,
            "operation_type" => operation.operation_type,
            "shared_payload" => operation.request_payload.fetch("shared_payload", {}),
            "targets" => targets.map { |target| target.except("node_id") }
          }

          operation.batches.create!(
            node: node,
            status: "ready",
            delivery_id: SecureRandom.uuid,
            payload: payload,
            payload_digest: Minecraft::NodeOperationDigest.call(payload),
            target_count: targets.length
          )
          nodes_to_wake << node
        end

        operation.update!(status: "ready", batch_count: targets_by_node.length)
      end

      nodes_to_wake.each(&:wake_for_tasks!)
    rescue ActiveRecord::RecordNotUnique
      # Another Sidekiq worker won the single global dispatch slot. Its terminal
      # reconciliation will schedule the next queued task group.
      raise unless Minecraft::NodeOperation.dispatching.exists?
    end
  end
end
