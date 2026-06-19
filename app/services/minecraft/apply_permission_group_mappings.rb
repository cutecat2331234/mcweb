# frozen_string_literal: true

module Minecraft
  class ApplyPermissionGroupMappings < ApplicationService
    def initialize(user:, player_profile:)
      @user = user
      @player_profile = player_profile
    end

    def call
      return ServiceResult.success(skipped: true) unless @user && @player_profile

      mappings = parse_mappings
      return ServiceResult.success(skipped: true) if mappings.empty?

      game_keys = @player_profile.permission_groups.pluck(:group_key)
      applied = []

      mappings.each do |mapping|
        next unless game_keys.include?(mapping["game_group"].to_s)

        if mapping["role_key"].present?
          role = Role.find_by(key: mapping["role_key"])
          if role && !@user.roles.exists?(id: role.id)
            @user.roles << role
            applied << "role:#{role.key}"
          end
        end

        if mapping["badge_slug"].present?
          result = Community::AwardBadge.call(user: @user, badge_slug: mapping["badge_slug"])
          applied << "badge:#{mapping['badge_slug']}" if result.success?
        end
      end

      ServiceResult.success(applied: applied)
    end

    private

    def parse_mappings
      JSON.parse(SiteSetting.get("minecraft.permission_group_mappings", "[]"))
    rescue JSON::ParserError
      []
    end
  end
end
