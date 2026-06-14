module Minecraft
  class ConnectorTask < ApplicationRecord
    belongs_to :server, class_name: "Minecraft::Server", foreign_key: :minecraft_server_id
    belongs_to :fulfillment, class_name: "Commerce::Fulfillment", foreign_key: :store_fulfillment_id, optional: true

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
