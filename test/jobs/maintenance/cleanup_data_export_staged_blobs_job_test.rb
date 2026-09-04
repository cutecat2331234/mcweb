# frozen_string_literal: true

require "test_helper"

module Maintenance
  class CleanupDataExportStagedBlobsJobTest < ActiveJob::TestCase
    test "delegates staged blob cleanup and is registered on maintenance" do
      now = Time.zone.parse("2026-09-04 12:00:00 UTC")
      calls = []
      cleanup = lambda do |now:|
        calls << now
        { scanned: 1, removed: 1, retained: 0, failed: 0 }.freeze
      end

      result = Identity::DataExportBlobCleanup.stub(:cleanup_staged!, cleanup) do
        CleanupDataExportStagedBlobsJob.perform_now(now:)
      end
      schedule = YAML.safe_load_file(Rails.root.join("config/sidekiq_cron.yml"))
        .fetch("cleanup_data_export_staged_blobs")

      assert_equal [ now ], calls
      assert_equal 1, result.fetch(:removed)
      assert_equal "50 * * * *", schedule.fetch("cron")
      assert_equal "Maintenance::CleanupDataExportStagedBlobsJob", schedule.fetch("class")
      assert_equal "maintenance", schedule.fetch("queue")
      assert_equal true, schedule.fetch("active_job")
    end
  end
end
