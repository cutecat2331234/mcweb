# frozen_string_literal: true

module Minecraft
  class AssertPlayerOnServer < ApplicationService
    def initialize(server:, player_ref:)
      @server = server
      @player_ref = player_ref
    end

    def call
      return ServiceResult.success if accessible_on_server?

      ServiceResult.failure(error: "Player is not associated with this server.")
    end

    private

    def accessible_on_server?
      profile_id = @player_ref.profile.id

      Minecraft::PlayerSession.active.for_server(@server).exists?(player_profile_id: profile_id)
    end
  end
end
