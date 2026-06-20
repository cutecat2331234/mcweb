# frozen_string_literal: true

module Commerce
  class BuildConnectorTaskPayload < ApplicationService
    PLAYER_PLACEHOLDER = "{player}"
    UUID_PLACEHOLDER = "{uuid}"

    def initialize(fulfillment:)
      @fulfillment = fulfillment
      @order_item = fulfillment.order_item
      @snapshot = @order_item.fulfillment_snapshot || {}
    end

    def call
      commands = extract_commands
      return ServiceResult.failure(error: "missing_commands") if commands.empty?

      if substitution_needed?(commands)
        player_ref = resolve_player_ref
        return ServiceResult.failure(error: "player_not_linked") unless player_ref

        player_name = player_ref.username
        player_uuid = player_ref.active_uuid
        return ServiceResult.failure(error: "player_not_linked") if player_name.blank? && player_uuid.blank?

        commands = commands.map { |command| substitute(command, player_name: player_name, player_uuid: player_uuid) }
      end

      ServiceResult.success(
        delivery_id: @fulfillment.delivery_id,
        order_item_id: @order_item.id,
        commands: commands,
        fulfillment_snapshot: @snapshot
      )
    end

    private

    def fulfillment_config
      config = @snapshot["fulfillment_config"] || @snapshot[:fulfillment_config] || {}
      config.with_indifferent_access
    end

    def extract_commands
      Array(fulfillment_config[:commands]).map(&:to_s).reject(&:blank?)
    end

    def substitution_needed?(commands)
      commands.any? { |command| command.include?(PLAYER_PLACEHOLDER) || command.include?(UUID_PLACEHOLDER) }
    end

    def resolve_player_ref
      user = @order_item.order.user
      link = user.minecraft_identity_links.active.includes(:player_profile).first
      return unless link

      Minecraft::PlayerRef.new(link.player_profile)
    end

    def substitute(command, player_name:, player_uuid:)
      command
        .gsub(PLAYER_PLACEHOLDER, player_name.to_s)
        .gsub(UUID_PLACEHOLDER, player_uuid.to_s)
    end
  end
end
