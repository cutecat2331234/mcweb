# frozen_string_literal: true

require "test_helper"

module Identity
  class DataExportBlobCleanupTest < ActiveSupport::TestCase
    test "cleanup reuses the durable cursor across batches" do
      cursor = DataExportBlobCleanupCursor.create!(
        name: DataExportBlobCleanup::CLEANUP_CURSOR_NAME,
        last_blob_id: 17,
        cycle_max_blob_id: 29
      )

      resolved = DataExportBlobCleanup.send(:cleanup_cursor)

      assert_equal cursor.id, resolved.id
      assert_equal 17, resolved.last_blob_id
      assert_equal 29, resolved.cycle_max_blob_id
    end

    test "staged cleanup removes old orphaned archives but preserves a live generation owner" do
      now = Time.zone.parse("2026-09-04 12:00:00 UTC")
      orphan = staged_blob(public_id: "missing-export", created_at: now - 3.hours)
      data_export = DataExport.create!(
        user: create_user,
        idempotency_key: "live-staged-blob-owner",
        requested_at: now - 3.hours,
        status: :running,
        started_at: now - 3.hours,
        attempts: 2
      )
      live_blob = staged_blob(
        public_id: data_export.public_id,
        request_revision: DataExportGeneration.request_revision(data_export),
        generation_attempt: data_export.attempts,
        created_at: now - 3.hours
      )

      result = DataExportGeneration.stub(:live_execution?, true) do
        DataExportBlobCleanup.cleanup_staged!(now:)
      end

      assert_equal({ scanned: 2, removed: 1, retained: 1, failed: 0 }, result)
      refute ActiveStorage::Blob.exists?(orphan.id)
      assert ActiveStorage::Blob.exists?(live_blob.id)
    ensure
      live_blob&.purge if live_blob&.persisted?
    end

    test "cleanup ignores unrelated unattached blobs" do
      now = Time.zone.parse("2026-09-04 12:00:00 UTC")
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("unrelated"),
        filename: "unrelated.zip",
        content_type: "application/zip",
        identify: false
      )
      blob.update_columns(created_at: now - 3.hours)

      result = DataExportBlobCleanup.cleanup_staged!(now:)

      assert_equal 0, result.fetch(:scanned)
      assert ActiveStorage::Blob.exists?(blob.id)
    ensure
      blob&.purge if blob&.persisted?
    end

    test "cleanup accepts only a native true staging marker" do
      now = Time.zone.parse("2026-09-04 12:00:00 UTC")
      blobs = [ false, "true", 1, "staged" ].map.with_index do |value, index|
        staged_blob(
          public_id: "false-staging-marker-#{index}",
          staging_value: value,
          created_at: now - 3.hours
        )
      end

      result = DataExportBlobCleanup.cleanup_staged!(now:)

      assert_equal 0, result.fetch(:scanned)
      blobs.each { |blob| assert ActiveStorage::Blob.exists?(blob.id) }
    ensure
      blobs&.each { |blob| blob.purge if blob.persisted? }
    end

    test "nested staging-like metadata cannot consume the cleanup limit" do
      now = Time.zone.parse("2026-09-04 12:00:00 UTC")
      nested = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("nested metadata"),
        filename: "nested-metadata.zip",
        content_type: "application/zip",
        metadata: {
          "unrelated" => { "identity_data_export_staging" => true }
        },
        identify: false
      )
      nested.update_columns(created_at: now - 4.hours)
      orphan = staged_blob(
        public_id: "real-orphan-behind-nested-marker",
        created_at: now - 3.hours
      )

      result = DataExportBlobCleanup.cleanup_staged!(now:, limit: 1)

      assert_equal({ scanned: 1, removed: 1, retained: 0, failed: 0 }, result)
      assert ActiveStorage::Blob.exists?(nested.id)
      refute ActiveStorage::Blob.exists?(orphan.id)
    ensure
      nested&.purge if nested&.persisted?
      orphan&.purge if orphan&.persisted?
    end

    test "persistent cursor reaches an orphan behind retained and failed blobs" do
      now = Time.zone.parse("2026-09-04 12:00:00 UTC")
      data_export = DataExport.create!(
        user: create_user,
        idempotency_key: "cleanup-cursor-live-owner",
        requested_at: now - 3.hours,
        status: :running,
        started_at: now - 3.hours,
        attempts: 1
      )
      retained = staged_blob(
        public_id: data_export.public_id,
        request_revision: DataExportGeneration.request_revision(data_export),
        generation_attempt: data_export.attempts,
        created_at: now - 3.hours
      )
      failed = staged_blob(
        public_id: "cleanup-cursor-purge-failure",
        created_at: now - 3.hours
      )
      reachable = staged_blob(
        public_id: "cleanup-cursor-reachable-orphan",
        created_at: now - 3.hours
      )
      original_purge = DataExportBlobCleanup.method(:purge_now)
      purge = lambda do |blob|
        blob.id == failed.id ? false : original_purge.call(blob)
      end

      first_result = DataExportGeneration.stub(:live_execution?, true) do
        DataExportBlobCleanup.stub(:purge_now, purge) do
          DataExportBlobCleanup.cleanup_staged!(now:, limit: 2)
        end
      end
      second_result = DataExportGeneration.stub(:live_execution?, true) do
        DataExportBlobCleanup.stub(:purge_now, purge) do
          DataExportBlobCleanup.cleanup_staged!(now:, limit: 2)
        end
      end

      assert_equal({ scanned: 2, removed: 0, retained: 1, failed: 1 }, first_result)
      assert_equal({ scanned: 1, removed: 1, retained: 0, failed: 0 }, second_result)
      assert ActiveStorage::Blob.exists?(retained.id)
      assert ActiveStorage::Blob.exists?(failed.id)
      refute ActiveStorage::Blob.exists?(reachable.id)
    ensure
      retained&.purge if retained&.persisted?
      failed&.purge if failed&.persisted?
      reachable&.purge if reachable&.persisted?
    end

    test "cursor wraps when the rest of its frozen cycle was deleted" do
      now = Time.zone.parse("2026-09-04 12:00:00 UTC")
      data_export = DataExport.create!(
        user: create_user,
        idempotency_key: "cleanup-cursor-wrap-owner",
        requested_at: now - 3.hours,
        status: :running,
        started_at: now - 3.hours,
        attempts: 1
      )
      retained = staged_blob(
        public_id: data_export.public_id,
        request_revision: DataExportGeneration.request_revision(data_export),
        generation_attempt: data_export.attempts,
        created_at: now - 3.hours
      )
      deleted = staged_blob(
        public_id: "cleanup-cursor-deleted-tail",
        created_at: now - 3.hours
      )

      first_result = DataExportGeneration.stub(:live_execution?, true) do
        DataExportBlobCleanup.cleanup_staged!(now:, limit: 1)
      end
      deleted.purge
      second_result = DataExportGeneration.stub(:live_execution?, true) do
        DataExportBlobCleanup.cleanup_staged!(now:, limit: 1)
      end

      assert_equal({ scanned: 1, removed: 0, retained: 1, failed: 0 }, first_result)
      assert_equal({ scanned: 1, removed: 0, retained: 1, failed: 0 }, second_result)
      cursor = DataExportBlobCleanupCursor.find_by!(
        name: DataExportBlobCleanup::CLEANUP_CURSOR_NAME
      )
      assert_equal retained.id, cursor.last_blob_id
      assert_equal retained.id, cursor.cycle_max_blob_id
    ensure
      retained&.purge if retained&.persisted?
      deleted&.purge if deleted&.persisted?
    end

    test "purge does not report success when a concurrent attachment keeps the blob" do
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("attach race"),
        filename: "attach-race.zip",
        content_type: "application/zip",
        identify: false
      )

      checks = 0
      attachments = Object.new
      attachments.define_singleton_method(:exists?) do
        checks += 1
        checks > 1
      end
      removed = blob.stub(:attachments, attachments) do
        DataExportBlobCleanup.purge_now(blob)
      end

      assert_equal false, removed
      assert ActiveStorage::Blob.exists?(blob.id)
    ensure
      blob&.purge if blob&.persisted?
    end

    test "remote deletion failure retains the blob locator for a later cleanup pass" do
      blob = staged_blob(
        public_id: "cleanup-retryable-storage-failure",
        created_at: 3.hours.ago
      )

      removed = blob.stub(:delete, -> { raise IOError, "storage unavailable" }) do
        DataExportBlobCleanup.purge_now(blob)
      end

      assert_equal false, removed
      assert ActiveStorage::Blob.exists?(blob.id)
    ensure
      blob&.purge if blob&.persisted?
    end

    private

    def staged_blob(
      public_id:,
      created_at:,
      request_revision: nil,
      generation_attempt: nil,
      staging_value: true
    )
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("private staged export"),
        filename: "staged.zip",
        content_type: "application/zip",
        metadata: {
          "identity_data_export_staging" => staging_value,
          "data_export_public_id" => public_id,
          "data_export_request_revision" => request_revision,
          "data_export_generation_attempt" => generation_attempt
        }.compact,
        identify: false
      )
      blob.update_columns(created_at:)
      blob
    end
  end
end
