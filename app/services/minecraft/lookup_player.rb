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
      membership = Commerce::MembershipSummary.for_user(user)
      trust_level_label = I18n.t("mcweb.labels.trust_level.tl#{level}", default: "TL#{level}")
      ServiceResult.success(
        linked: true,
        player_id: player_ref.public_id,
        minecraft_username: identity.username,
        uuid: identity.external_uuid,
        website_username: user.username,
        display_name: user.display_name.presence || user.username,
        trust_level: level,
        trust_level_label: trust_level_label,
        roles: user.roles.pluck(:name),
        memberships: membership[:memberships],
        membership_labels: membership[:membership_labels],
        membership_primary: membership[:membership_primary],
        membership_expires_at: membership[:membership_expires_at],
        whois_lines: build_whois_lines(user:, trust_level_label:, membership:),
        message: I18n.t("mcweb.minecraft.whois.linked_summary", username: user.username)
      )
    end

    private

    def build_whois_lines(user:, trust_level_label:, membership:)
      lines = [
        I18n.t("mcweb.minecraft.whois.website", username: user.username),
        I18n.t("mcweb.minecraft.whois.trust", label: trust_level_label)
      ]
      if membership[:membership_labels].present?
        lines << I18n.t("mcweb.minecraft.whois.membership", labels: membership[:membership_labels])
      end
      if membership[:membership_expires_at].present?
        lines << I18n.t("mcweb.minecraft.whois.membership_expires", expires: membership[:membership_expires_at])
      end
      lines
    end

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
