# frozen_string_literal: true

module Maintenance
  class CleanupDataExportTempfilesJob < ApplicationJob
    queue_as :maintenance

    def perform(now: Time.current)
      result = Identity::DataExportTemporaryStorage.cleanup_orphans!(now:)
      if result.fetch(:failed).positive?
        Rails.logger.warn(
          "data export temporary cleanup incomplete: " \
          "removed=#{result.fetch(:removed)} failed=#{result.fetch(:failed)}"
        )
      end
      result
    end
  end
end
