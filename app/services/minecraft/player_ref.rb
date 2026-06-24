# frozen_string_literal: true

module Minecraft
  class PlayerRef
    attr_reader :profile

    delegate :public_id, to: :profile, prefix: false
    alias_method :player_id, :public_id

    def initialize(profile)
      @profile = profile
    end

    def self.find_by_canonical(id)
      profile = PlayerProfile.find_by_public_id(id)
      profile ? new(profile) : nil
    end

    def self.resolve(uuid:, platform: "java", username: nil, identity_type: "java")
      identity = PlayerIdentity.active.find_by(platform: platform, external_uuid: uuid)
      if identity
        return new(identity.player_profile)
      end

      profile = nil
      ActiveRecord::Base.transaction do
        profile = PlayerProfile.create!
        PlayerIdentity.create!(
          player_profile: profile,
          platform: platform,
          external_uuid: uuid,
          username: username.presence || uuid,
          identity_type: identity_type,
          valid_from: Time.current
        )
      end
      new(profile)
    rescue ActiveRecord::RecordNotUnique
      # Concurrent first-touch for the same uuid: the partial-unique index raced us.
      # Re-resolve the row the winner created instead of surfacing a 500.
      identity = PlayerIdentity.active.find_by(platform: platform, external_uuid: uuid)
      raise unless identity

      new(identity.player_profile)
    end

    def active_uuid(platform: "java")
      active_identity(platform: platform)&.external_uuid
    end

    def username(platform: "java")
      active_identity(platform: platform)&.username
    end

    def website_user
      profile.website_user
    end

    def active_identity(platform: "java")
      profile.active_identity(platform: platform)
    end

    def link_user!(user)
      return if profile.identity_links.active.exists?(user: user)
      raise ArgumentError, "User already linked" if profile.identity_links.active.exists?

      IdentityLink.create!(
        player_profile: profile,
        user: user,
        linked_at: Time.current
      )
    end
  end
end
