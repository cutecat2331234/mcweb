# frozen_string_literal: true

module Minecraft
  class IdentityLink < ApplicationRecord
    belongs_to :player_profile, class_name: "Minecraft::PlayerProfile"
    belongs_to :user

    validates :linked_at, presence: true

    scope :active, -> { where(unlinked_at: nil) }

    def unlink!
      update!(unlinked_at: Time.current)
    end
  end
end
