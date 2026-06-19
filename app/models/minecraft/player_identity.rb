# frozen_string_literal: true

module Minecraft
  class PlayerIdentity < ApplicationRecord
    belongs_to :player_profile, class_name: "Minecraft::PlayerProfile"
    belongs_to :primary_server, class_name: "Minecraft::Server", optional: true

    validates :platform, :external_uuid, :username, :identity_type, :valid_from, presence: true
    validates :external_uuid, uniqueness: { scope: :platform, conditions: -> { where(superseded_at: nil) } }

    scope :active, -> { where(superseded_at: nil) }

    def supersede!
      update!(superseded_at: Time.current)
    end
  end
end
