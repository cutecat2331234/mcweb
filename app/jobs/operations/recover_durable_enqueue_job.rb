# frozen_string_literal: true

module Operations
  class RecoverDurableEnqueueJob < ApplicationJob
    queue_as :maintenance

    def perform(limit = Operations::RecoverDurableEnqueue::DEFAULT_LIMIT)
      Operations::RecoverDurableEnqueue.call(limit:, trigger: "maintenance")
    end
  end
end
