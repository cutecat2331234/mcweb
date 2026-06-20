# frozen_string_literal: true

module Commerce
  class BuildMembershipCommandPayload < ApplicationService
    PLAYER_PLACEHOLDER = "{player}"
    UUID_PLACEHOLDER = "{uuid}"
    GROUP_PLACEHOLDER = "{group}"
    DURATION_PLACEHOLDER = "{duration}"

    def initialize(user:, membership_type:, commands:)
      @user = user
      @membership_type = membership_type
      @commands = Array(commands).map(&:to_s).reject(&:blank?)
    end

    def call
      return ServiceResult.failure(error: "missing_commands") if @commands.empty?

      player_ref = resolve_player_ref
      return ServiceResult.failure(error: "player_not_linked") unless player_ref

      player_name = player_ref.username
      player_uuid = player_ref.active_uuid
      return ServiceResult.failure(error: "player_not_linked") if player_name.blank? && player_uuid.blank?

      group = @membership_type.luckperms_group.presence || @membership_type.slug
      duration = "#{@membership_type.duration_days}d"

      substituted = @commands.map do |command|
        command
          .gsub(PLAYER_PLACEHOLDER, player_name.to_s)
          .gsub(UUID_PLACEHOLDER, player_uuid.to_s)
          .gsub(GROUP_PLACEHOLDER, group)
          .gsub(DURATION_PLACEHOLDER, duration)
      end

      ServiceResult.success(commands: substituted)
    end

    private

    def resolve_player_ref
      link = @user.minecraft_identity_links.active.includes(:player_profile).first
      return unless link

      Minecraft::PlayerRef.new(link.player_profile)
    end
  end
end
