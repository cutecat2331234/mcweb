# frozen_string_literal: true

module Maintenance
  class PurgeGovernedContentJob < ApplicationJob
    queue_as :maintenance

    def perform(limit: 200, at: Time.current)
      DataGovernance::ContentLifecycleRecord
        .due_for_purge(at)
        .order(:purge_after, :id)
        .limit(limit)
        .each do |record|
          DataGovernance::PermanentlyPurgeContent.call(
            record:,
            reason: "scheduled_retention_expiry",
            at:
          )
        end
    end
  end
end
