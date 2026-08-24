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
      assert_enqueued_jobs 1, only: Operations::DispatchDurableIntentJob do
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
      data_export = first.value.fetch(:data_export)
      intent = Operations::DurableEnqueueIntent.find_by!(
        handler_key: Identity::DataExportGeneration::HANDLER_KEY,
        source_id: data_export.id
      )
      assert_equal "identity.data_export", intent.source_kind
      assert_equal "default", intent.queue_name
      assert_empty intent.arguments
      assert AuditLog.exists?(
        action: "identity.data_export_requested",
        resource_id: data_export.id
      )
    end

    test "request rolls back instead of reporting success when its durable intent cannot be recorded" do
      assert_no_difference -> { DataExport.count } do
        Identity::DataExportGeneration.stub(
          :record!,
          ->(**) { raise Operations::DurableEnqueueAdmission::Unavailable }
        ) do
          result = RequestDataExport.call(
            user: @user,
            idempotency_key: "export-admission-unavailable",
            ip_address: "127.0.0.1"
          )

          assert_predicate result, :failure?
          assert_equal "background_processing_unavailable", result.code
        end
      end
    end

    test "a queue outage leaves the accepted export queued and recoverable from PostgreSQL" do
      result = nil
      Operations::DispatchDurableIntentJob.stub(
        :set,
        ->(**) { raise IOError, "temporary queue outage" }
      ) do
        result = RequestDataExport.call(
          user: @user,
          idempotency_key: "export-redis-outage",
          ip_address: "127.0.0.1"
        )
      end

      assert_predicate result, :success?
      data_export = result.value.fetch(:data_export)
      assert_predicate data_export.reload, :queued?
      intent = Operations::DurableEnqueueIntent.find_by!(
        handler_key: Identity::DataExportGeneration::HANDLER_KEY,
        source_id: data_export.id
      )
      failure = intent.events.order(:sequence).last
      assert_equal "enqueue_failed", failure.event_type

      recovery_at = failure.occurred_at +
        Operations::DurableEnqueueCatalog.entry(intent.handler_key).enqueue_stale_seconds +
        1.second
      assert_enqueued_with(job: Operations::DispatchDurableIntentJob, queue: "default") do
        recovery = Operations::RecoverDurableEnqueue.call(
          now: recovery_at,
          intent_public_ids: [ intent.public_id ]
        )

        assert_predicate recovery, :success?
        assert_equal 1, recovery.value.fetch(:enqueued_count)
        assert_equal [ intent.public_id ], recovery.value.fetch(:intent_public_ids)
      end
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
      manifest = JSON.parse(files.fetch("manifest.json"))
      assert_equal 2, manifest.fetch("schema_version")
      assert_equal 1, manifest.dig("modules", "identity.profile", "record_count")
      assert_equal 1, manifest.dig("modules", "identity.notifications", "record_count")
      assert_equal manifest, data_export.manifest
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

      assert_enqueued_jobs 1, only: Operations::DispatchDurableIntentJob do
        result = RetryDataExport.call(data_export:, user: @user)
        assert result.success?
        refute result.value.fetch(:replayed)
      end

      assert_predicate data_export.reload, :queued?
      assert_nil data_export.error_code
    end

    test "retry keeps the failed state when a new durable generation cannot be recorded" do
      requested_at = 1.hour.ago
      data_export = DataExport.create!(
        user: @user,
        idempotency_key: "retry-export-admission-unavailable",
        requested_at:,
        status: :failed,
        failed_at: Time.current,
        error_code: "data_export_generation_failed"
      )

      Identity::DataExportGeneration.stub(
        :record!,
        ->(**) { raise Operations::DurableEnqueueAdmission::Unavailable }
      ) do
        result = RetryDataExport.call(data_export:, user: @user)

        assert_predicate result, :failure?
        assert_equal "background_processing_unavailable", result.code
      end

      data_export.reload
      assert_predicate data_export, :failed?
      assert_equal "data_export_generation_failed", data_export.error_code
      assert_equal requested_at.to_i, data_export.requested_at.to_i
    end

    test "a contributor failure retries the same logical export and completes on a later attempt" do
      calls = 0
      registry = DataExportRegistry.new
      registry.register(
        key: "sample.transient",
        contributor: ->(context:) do
          calls += 1
          raise "transient private failure" if calls == 1

          DataExporting::Contribution.new(
            documents: { "sample.json" => [ { "user" => context.user.public_id } ] }
          )
        end
      )
      data_export = DataExport.create!(
        user: @user,
        idempotency_key: "retry-contributor-export-1",
        requested_at: Time.current
      )

      DataExportCatalog.stub(:entries, registry.entries) do
        BuildDataExportJob.perform_now(data_export.id)

        assert_predicate data_export.reload, :failed?
        assert_equal "data_export_contributor_failed", data_export.error_code
        assert_equal 1, data_export.attempts

        assert_no_difference -> { DataExport.count } do
          assert_enqueued_jobs 1, only: Operations::DispatchDurableIntentJob do
            result = RetryDataExport.call(data_export:, user: @user)
            assert_predicate result, :success?
          end
        end

        BuildDataExportJob.perform_now(data_export.id)
      end

      assert_predicate data_export.reload, :completed?
      assert_equal 2, data_export.attempts
      assert_equal 1, data_export.manifest.dig("modules", "sample.transient", "record_count")
    end
  end
end
