# frozen_string_literal: true

require "test_helper"
require "zip"

module Identity
  class DataExportLifecycleTest < ActiveSupport::TestCase
    setup do
      @user = create_user(display_name: "Export Member")
      Notification.create!(
        user: @user,
        notification_type: "account.test",
        title: "Export notification",
        body: "Owned notification"
      )
    end

    test "request is idempotent and queues a single background export" do
      first = nil
      assert_enqueued_jobs 1, only: BuildDataExportJob do
        first = RequestDataExport.call(
          user: @user,
          idempotency_key: "export-request-1",
          ip_address: "127.0.0.1"
        )
        replay = RequestDataExport.call(
          user: @user,
          idempotency_key: "export-request-1",
          ip_address: "127.0.0.1"
        )

        assert replay.success?
        assert replay.value.fetch(:replayed)
        assert_equal first.value.fetch(:data_export), replay.value.fetch(:data_export)
      end

      assert first.success?
      assert AuditLog.exists?(
        action: "identity.data_export_requested",
        resource_id: first.value.fetch(:data_export).id
      )
    end

    test "job creates a private zip without authentication secrets" do
      data_export = DataExport.create!(
        user: @user,
        idempotency_key: "build-export-1",
        requested_at: Time.current
      )

      BuildDataExportJob.perform_now(data_export.id)

      data_export.reload
      assert_predicate data_export, :completed?
      assert_predicate data_export, :downloadable?
      assert data_export.expires_at > 71.hours.from_now
      assert data_export.archive.attached?

      files = {}
      Zip::File.open_buffer(data_export.archive.download) do |zip|
        zip.each { |entry| files[entry.name] = entry.get_input_stream.read }
      end
      assert_includes files.keys, "profile.json"
      assert_includes files.keys, "notifications.json"
      assert_includes files.fetch("profile.json"), @user.email
      refute_includes files.values.join, @user.password_digest
      refute_includes files.values.join, "totp_secret"
      refute_includes files.values.join, "recovery_codes"
    end

    test "revocation removes download eligibility and retry only accepts failed or expired exports" do
      data_export = DataExport.create!(
        user: @user,
        idempotency_key: "revoke-export-1",
        requested_at: Time.current,
        status: :completed,
        completed_at: Time.current,
        expires_at: 1.hour.from_now
      )
      data_export.archive.attach(
        io: StringIO.new("archive"),
        filename: "export.zip",
        content_type: "application/zip"
      )

      result = RevokeDataExport.call(data_export:, user: @user)

      assert result.success?
      assert_predicate data_export.reload, :revoked?
      refute_predicate data_export, :downloadable?
      assert AuditLog.exists?(action: "identity.data_export_revoked", resource_id: data_export.id)

      retry_result = RetryDataExport.call(data_export:, user: @user)
      assert retry_result.failure?
      assert_equal "data_export_retry_not_allowed", retry_result.code
    end

    test "failed export can be retried without creating another logical request" do
      data_export = DataExport.create!(
        user: @user,
        idempotency_key: "retry-export-1",
        requested_at: 1.hour.ago,
        status: :failed,
        failed_at: Time.current,
        error_code: "data_export_generation_failed"
      )

      assert_enqueued_jobs 1, only: BuildDataExportJob do
        result = RetryDataExport.call(data_export:, user: @user)
        assert result.success?
        refute result.value.fetch(:replayed)
      end

      assert_predicate data_export.reload, :queued?
      assert_nil data_export.error_code
    end
  end
end
