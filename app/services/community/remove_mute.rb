# frozen_string_literal: true

module Community
  class RemoveMute < ApplicationService
    def initialize(actor:, mute:)
      @actor = actor
      @mute = mute
    end

    def call
      unless @actor.permission?("forum.users.mute")
        return ServiceResult.failure(error: "Not authorized.")
      end

      @mute.destroy!
      ServiceResult.success
    end
  end
end
