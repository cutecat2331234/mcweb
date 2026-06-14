module Minecraft
  class ProcessedDelivery < ApplicationRecord
    belongs_to :server, class_name: "Minecraft::Server", foreign_key: :minecraft_server_id

    validates :delivery_id, presence: true, uniqueness: { scope: :minecraft_server_id }
    validates :status, presence: true

    def self.already_processed?(server, delivery_id)
      exists?(server: server, delivery_id: delivery_id)
    end

    def self.record!(server:, delivery_id:, status:, result: {})
      create!(server: server, delivery_id: delivery_id, status: status, result: result)
    end
  end
end
