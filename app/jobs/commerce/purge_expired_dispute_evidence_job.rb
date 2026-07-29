# frozen_string_literal: true

module Commerce
  class PurgeExpiredDisputeEvidenceJob < ApplicationJob
    queue_as :maintenance

    def perform(limit: 200)
      Commerce::DisputeEvidence.retention_due
        .includes(:dispute)
        .order(:retention_until, :id)
        .limit(limit)
        .find_each do |evidence|
          Commerce::Disputes::PurgeEvidence.call(evidence: evidence)
        end
    end
  end
end
