# frozen_string_literal: true

require "test_helper"

module Maintenance
  class CleanupDataExportTempfilesJobTest < ActiveJob::TestCase
    test "delegates orphan cleanup with the requested cutoff time" do
      now = Time.zone.parse("2026-09-04 12:00:00 UTC")
      calls = []
      cleanup = lambda do |now:|
        calls << now
        { scanned: 2, removed: 1, retained: 1, failed: 0 }.freeze
      end

      result = Identity::DataExportTemporaryStorage.stub(:cleanup_orphans!, cleanup) do
        CleanupDataExportTempfilesJob.perform_now(now:)
      end

      assert_equal [ now ], calls
      assert_equal 1, result.fetch(:removed)
      assert_equal 0, result.fetch(:failed)
    end

    test "hourly cleanup is registered on the maintenance queue" do
      schedule = YAML.safe_load_file(Rails.root.join("config/sidekiq_cron.yml"))
      cleanup = schedule.fetch("cleanup_data_export_tempfiles")

      assert_equal "35 * * * *", cleanup.fetch("cron")
      assert_equal "Maintenance::CleanupDataExportTempfilesJob", cleanup.fetch("class")
      assert_equal "maintenance", cleanup.fetch("queue")
      assert_equal true, cleanup.fetch("active_job")
    end
  end
end
