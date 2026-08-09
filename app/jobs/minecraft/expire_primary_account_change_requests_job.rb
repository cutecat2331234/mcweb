# frozen_string_literal: true

module Minecraft
  class ExpirePrimaryAccountChangeRequestsJob < ApplicationJob
    queue_as :maintenance

    def perform
      Minecraft::ExpirePrimaryAccountChangeRequests.call
    end
  end
end
