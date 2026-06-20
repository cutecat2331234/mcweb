# frozen_string_literal: true

module Minecraft
  class RunIntegrationActionJob < ApplicationJob
    queue_as :minecraft

    def perform(event_key:, event_id:, payload: {})
      Minecraft::Integration::ActionRunner.call(
        event_key: event_key,
        event_id: event_id,
        payload: payload
      )
    end
  end
end
