# frozen_string_literal: true

module Minecraft
  class LookupPlayer < ApplicationService
    def initialize(uuid: nil, username: nil, platform: "java")
      @uuid = uuid
      @username = username
      @platform = platform
    end

    def call
      identity = find_identity
      unless identity
        return ServiceResult.success(
          linked: false,
          minecraft_username: @username,
          uuid: @uuid,
          message: I18n.t("mcweb.minecraft.whois.not_found")
        )
      end

      player_ref = PlayerRef.new(identity.player_profile)
      user = player_ref.website_user
      unless user
        return ServiceResult.success(
          linked: false,
          player_id: player_ref.public_id,
          minecraft_username: identity.username,
          uuid: identity.external_uuid,
          message: I18n.t("mcweb.minecraft.whois.not_linked")
        )
      end

      level = Community::TrustLevel.level_for(user)
      ServiceResult.success(
        linked: true,
        player_id: player_ref.public_id,
        minecraft_username: identity.username,
        uuid: identity.external_uuid,
        website_username: user.username,
        display_name: user.display_name.presence || user.username,
        trust_level: level,
        trust_level_label: I18n.t("mcweb.labels.trust_level.tl#{level}", default: "TL#{level}"),
        roles: user.roles.pluck(:name),
        message: I18n.t("mcweb.minecraft.whois.linked_summary", username: user.username)
      )
    end

    private

    def find_identity
      if @uuid.present?
        return PlayerIdentity.active.find_by(platform: @platform, external_uuid: @uuid)
      end

      return nil if @username.blank?

      PlayerIdentity.active.where(platform: @platform)
                      .where("LOWER(username) = ?", @username.downcase)
                      .order(valid_from: :desc)
                      .first
    end
  end
end
