# frozen_string_literal: true

module Minecraft
  class ProfileFieldValue < ApplicationRecord
    belongs_to :player_profile, class_name: "Minecraft::PlayerProfile"

    validates :field_key, presence: true, uniqueness: { scope: :player_profile_id }
  end
end
