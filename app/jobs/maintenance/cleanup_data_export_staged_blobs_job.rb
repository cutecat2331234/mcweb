# frozen_string_literal: true

module Maintenance
  class CleanupDataExportStagedBlobsJob < ApplicationJob
    queue_as :maintenance

    def perform(now: Time.current)
      result = Identity::DataExportBlobCleanup.cleanup_staged!(now:)
      if result.fetch(:failed).positive?
        Rails.logger.warn(
          "data export staged blob cleanup incomplete: " \
            "removed=#{result.fetch(:removed)} failed=#{result.fetch(:failed)}"
        )
      end
      result
    end
  end
end
