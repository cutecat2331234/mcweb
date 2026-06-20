# frozen_string_literal: true

module Minecraft
  class PlayerProfile < ApplicationRecord
    include HasPublicId

    has_many :player_identities, class_name: "Minecraft::PlayerIdentity", foreign_key: :player_profile_id, dependent: :destroy
    has_many :identity_links, class_name: "Minecraft::IdentityLink", foreign_key: :player_profile_id, dependent: :destroy
    has_many :users, through: :identity_links
    has_many :permission_groups, class_name: "Minecraft::PermissionGroup", foreign_key: :player_profile_id, dependent: :destroy
    has_many :profile_field_values, class_name: "Minecraft::ProfileFieldValue", foreign_key: :player_profile_id, dependent: :destroy
    has_many :player_sessions, class_name: "Minecraft::PlayerSession", foreign_key: :player_profile_id, dependent: :destroy
    has_many :legacy_identities, class_name: "Minecraft::Identity", foreign_key: :player_profile_id, dependent: :nullify

    def active_identity(platform: "java")
      player_identities.active.find_by(platform: platform)
    end

    def website_user
      identity_links.active.includes(:user).first&.user
    end
  end
end
