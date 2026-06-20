# frozen_string_literal: true

module Minecraft
  class PlayerSession < ApplicationRecord
    belongs_to :player_profile, class_name: "Minecraft::PlayerProfile"
    belongs_to :server, class_name: "Minecraft::Server", foreign_key: :minecraft_server_id

    scope :active, -> { where(ended_at: nil) }
    scope :for_server, ->(server) { where(minecraft_server_id: server.id) }

    def active?
      ended_at.nil?
    end

    def close!(at: Time.current)
      update!(ended_at: at) if ended_at.nil?
    end
  end
end
