# frozen_string_literal: true

module Minecraft
  class NodeTask < ApplicationRecord
    belongs_to :node, class_name: "Minecraft::Node", foreign_key: :minecraft_node_id
    belongs_to :server, class_name: "Minecraft::Server", foreign_key: :minecraft_server_id, optional: true

    enum :status, { pending: "pending", claimed: "claimed", completed: "completed", failed: "failed" }, validate: true

    validates :task_type, presence: true

    scope :claimable, -> { where(status: :pending).order(:created_at) }

    def claim!
      update!(status: :claimed, claimed_at: Time.current)
    end

    def complete!(result_data = {})
      update!(status: :completed, result: result_data, completed_at: Time.current)
    end

    def fail!(result_data = {})
      update!(status: :failed, result: result_data, completed_at: Time.current)
    end
  end
end
