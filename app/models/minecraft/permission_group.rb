# frozen_string_literal: true

module Minecraft
  class PermissionGroup < ApplicationRecord
    belongs_to :player_profile, class_name: "Minecraft::PlayerProfile"

    validates :group_key, presence: true, uniqueness: { scope: :player_profile_id }
    validates :source, presence: true
  end
end
