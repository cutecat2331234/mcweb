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

      granted_roles = apply_role_mappings(mappings, game_keys)
      apply_matching_mappings(mappings, game_keys, granted_roles, applied)

      ServiceResult.success(applied: applied)
    end

    private

    def apply_role_mappings(mappings, game_keys)
      matching_roles = mappings.each_with_index.filter_map do |mapping, index|
        next unless game_keys.include?(mapping["game_group"].to_s)
        next if mapping["role_key"].blank?

        [ index, mapping["role_key"].to_s ]
      end
      return {} if matching_roles.empty?

      granted_roles = {}
      ::Identity::PermissionMutationLock.with_exclusive do
        user = User.lock.find(@user.id)

        matching_roles.each do |index, role_key|
          role = Role.find_by(key: role_key)
          next unless role
          next if UserRole.exists?(user:, role:)

          UserRole.create!(user:, role:)
          granted_roles[index] = role.key
        end
      end
      granted_roles
    end

    def apply_matching_mappings(mappings, game_keys, granted_roles, applied)
      mappings.each_with_index do |mapping, index|
        next unless game_keys.include?(mapping["game_group"].to_s)

        applied << "role:#{granted_roles.fetch(index)}" if granted_roles.key?(index)

        if mapping["badge_slug"].present?
          result = Community::AwardBadge.call(user: @user, badge_slug: mapping["badge_slug"])
          applied << "badge:#{mapping['badge_slug']}" if result.success?
        end
      end
    end

    def parse_mappings
      JSON.parse(SiteSetting.get("minecraft.permission_group_mappings", "[]"))
    rescue JSON::ParserError
      []
    end
  end
end
