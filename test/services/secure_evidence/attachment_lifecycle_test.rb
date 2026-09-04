# frozen_string_literal: true

require "test_helper"
require "tempfile"

module SecureEvidence
  class AttachmentLifecycleTest < ActiveSupport::TestCase
    setup do
      @actor = create_user
      @download_allowed = true
      @discard_allowed = true
      @attachment_linked = false
      @retention_period = 30.days
      @registry = build_registry
      @temporary_files = []
    end

    teardown do
      @temporary_files.each(&:close!)
    end

    test "creates one inspected quota-accounted attachment and replays only an identical request" do
      first = create_attachment(file: uploaded_file("plain evidence"))
      replay = create_attachment(file: uploaded_file("plain evidence"))
      conflict = create_attachment(file: uploaded_file("different evidence"))

      assert_predicate first, :success?
      assert_equal false, first.value.fetch(:idempotent)
      assert_predicate replay, :success?
      assert_equal true, replay.value.fetch(:idempotent)
      assert_equal first.value.fetch(:attachment), replay.value.fetch(:attachment)
      assert_predicate conflict, :failure?
      assert_equal "secure_evidence_idempotency_conflict", conflict.code
      assert_equal 1, Attachment.where(uploader: @actor).count

      attachment = first.value.fetch(:attachment)
      upload = attachment.upload_record
      assert_equal "pending", attachment.state
      assert_equal "secure_evidence_attachment", upload.kind
      assert_equal "stored", upload.status
      assert_equal attachment.byte_size, upload.byte_size
      assert_equal 1, attachment.events.where(event_type: "created").count
      assert_equal 1, attachment.events.where(event_type: "upload_stored").count
      assert AuditLog.exists?(action: "secure_evidence.created", resource_public_id: attachment.public_id)
    end

    test "failed storage is tracked cleaned and retried on the same attachment" do
      registry = build_registry(max_files: 1)
      SiteSetting.set("forum.upload_quota.account.hourly_count", "1")
      original_upload = ActiveStorage::Blob.instance_method(:upload_without_unfurling)
      ActiveStorage::Blob.define_method(:upload_without_unfurling) do |_io|
        raise Timeout::Error, "object storage response timed out"
      end

      failed = create_attachment(
        file: uploaded_file("retryable storage failure"),
        key: "evidence-storage-retry-0001",
        registry:
      )
      assert_predicate failed, :failure?
      assert_equal "secure_evidence_upload_failed", failed.code

      attachment = Attachment.find_by!(
        uploader: @actor,
        idempotency_key: "evidence-storage-retry-0001"
      )
      first_upload = attachment.upload_record
      first_blob_id = first_upload.active_storage_blob_id
      assert_equal "upload_failed", attachment.state
      assert_equal "cleanup_failed", first_upload.status
      assert_equal "pending", first_upload.scan_status
      assert_operator first_upload.expires_at, :>, Time.current
      refute Community::Upload.cleanup_due(Time.current).exists?(first_upload.id)
      assert ActiveStorage::Blob.exists?(first_blob_id)
      refute AttachmentAccess.download_allowed?(
        attachment,
        actor: @actor,
        catalog: registry
      )
      refute enqueued_jobs.any? { |job| job[:job] == Community::ScanPostAttachmentJob }

      pending_retry = create_attachment(
        file: uploaded_file("retryable storage failure"),
        key: "evidence-storage-retry-0001",
        registry:
      )
      assert_predicate pending_retry, :failure?
      assert_equal "secure_evidence_upload_retry_pending", pending_retry.code
      assert_equal 1, Community::Upload.where(
        user: @actor,
        kind: "secure_evidence_attachment"
      ).count

      other_key = create_attachment(
        file: uploaded_file("other evidence while cleanup is pending"),
        key: "evidence-storage-retry-0002",
        registry:
      )
      assert_predicate other_key, :failure?
      assert_equal "secure_evidence_file_limit_exceeded", other_key.code

      early_cleanup = Community::CleanupUpload.call(upload: first_upload, now: Time.current)
      assert_predicate early_cleanup, :success?
      assert_equal "not_due", early_cleanup.value.fetch(:skipped)

      cleanup = Community::CleanupUpload.call(
        upload: first_upload,
        now: first_upload.expires_at + 1.second
      )
      assert_predicate cleanup, :success?
      assert_equal "upload_failed", attachment.reload.state
      assert_equal "cleaned", first_upload.reload.status
      refute ActiveStorage::Blob.exists?(first_blob_id)

      ActiveStorage::Blob.define_method(:upload_without_unfurling, original_upload)
      retried = create_attachment(
        file: uploaded_file("retryable storage failure"),
        key: "evidence-storage-retry-0001",
        registry:
      )

      assert_predicate retried, :success?
      assert_equal true, retried.value.fetch(:idempotent)
      assert_equal attachment.id, retried.value.fetch(:attachment).id
      assert_equal "pending", attachment.reload.state
      attempts = Community::Upload.where(
        user: @actor,
        kind: "secure_evidence_attachment"
      ).order(:id)
      assert_equal [ first_upload.id ], attempts.pluck(:id)
      assert_equal [ "stored" ], attempts.pluck(:status)
      assert_equal 1, attempts.counted_toward_quota.count
      assert_equal 1, attachment.events.where(event_type: "upload_failed").count
      assert_equal 1, attachment.events.where(event_type: "upload_retried").count
      assert_equal 1, attachment.events.where(event_type: "upload_stored").count
    ensure
      ActiveStorage::Blob.define_method(:upload_without_unfurling, original_upload) if original_upload
    end

    test "a lost finalize acknowledgement reconciles the committed upload" do
      original_finalize = StoreAttachmentUpload.instance_method(:finalize_upload!)
      StoreAttachmentUpload.define_method(:finalize_upload!) do
        original_finalize.bind_call(self)
        raise IOError, "simulated lost commit acknowledgement"
      end
      StoreAttachmentUpload.send(:private, :finalize_upload!)

      result = create_attachment(
        file: uploaded_file("commit acknowledgement evidence"),
        key: "evidence-commit-ack-0001"
      )

      assert_predicate result, :success?
      attachment = result.value.fetch(:attachment)
      upload = attachment.upload_record
      assert_equal "pending", attachment.state
      assert_equal "stored", upload.status
      assert upload.blob.present?
      assert_equal 1, attachment.events.where(event_type: "upload_stored").count
      assert_equal 0, attachment.events.where(event_type: "upload_failed").count
      assert_enqueued_with(
        job: Community::ScanPostAttachmentJob,
        args: [ { upload_id: upload.id } ]
      )
    ensure
      if original_finalize
        StoreAttachmentUpload.define_method(:finalize_upload!, original_finalize)
        StoreAttachmentUpload.send(:private, :finalize_upload!)
      end
    end

    test "maintenance reconciles an uploading attempt abandoned after remote storage" do
      original_upload = ActiveStorage::Blob.instance_method(:upload_without_unfurling)
      ActiveStorage::Blob.define_method(:upload_without_unfurling) do |io|
        original_upload.bind_call(self, io)
        raise SystemExit, "simulated worker loss"
      end

      assert_raises(SystemExit) do
        create_attachment(
          file: uploaded_file("abandoned after storage"),
          key: "evidence-abandoned-upload-0001"
        )
      end
      attachment = Attachment.find_by!(
        uploader: @actor,
        idempotency_key: "evidence-abandoned-upload-0001"
      )
      upload = attachment.upload_record
      blob_id = upload.active_storage_blob_id
      assert_equal "uploading", attachment.state
      assert_equal "reserved", upload.status
      assert ActiveStorage::Blob.exists?(blob_id)
      refute AttachmentAccess.download_allowed?(
        attachment,
        actor: @actor,
        catalog: @registry
      )

      ActiveStorage::Blob.define_method(:upload_without_unfurling, original_upload)
      upload.update!(expires_at: 1.minute.ago)
      assert Community::Upload.cleanup_due(Time.current).exists?(upload.id)
      cleanup = Community::CleanupUpload.call(upload:, now: Time.current)

      assert_predicate cleanup, :success?
      assert_equal "upload_failed", attachment.reload.state
      assert_equal "cleaned", upload.reload.status
      refute ActiveStorage::Blob.exists?(blob_id)
      failure_event = attachment.events.find_by!(event_type: "upload_failed")
      assert_equal "secure_evidence_upload_timeout", failure_event.metadata.fetch("failure_code")
    ensure
      ActiveStorage::Blob.define_method(:upload_without_unfurling, original_upload) if original_upload
    end

    test "rejects spoofed executable content and enforces per-subject file limit" do
      rejected = create_attachment(file: uploaded_file("MZmalware", filename: "claim.txt"))
      assert_predicate rejected, :failure?
      assert_equal "unsupported_attachment_type", rejected.code

      registry = build_registry(max_files: 1)
      first = create_attachment(file: uploaded_file("first"), registry:, key: "evidence-key-0001")
      second = create_attachment(file: uploaded_file("second"), registry:, key: "evidence-key-0002")

      assert_predicate first, :success?
      assert_predicate second, :failure?
      assert_equal "secure_evidence_file_limit_exceeded", second.code

      total_registry = build_registry(max_file_bytes: 10, max_total_bytes: 10)
      total_exceeded = create_attachment(
        file: uploaded_file("second"),
        registry: total_registry,
        key: "evidence-key-0003"
      )
      assert_predicate total_exceeded, :failure?
      assert_equal "secure_evidence_total_size_exceeded", total_exceeded.code
    end

    test "uploader can idempotently discard an unlinked draft and release subject quota" do
      registry = build_registry(max_files: 1)
      attachment = create_attachment(
        file: uploaded_file("replace me"),
        registry:,
        key: "evidence-discard-0001"
      ).value.fetch(:attachment)

      callbacks = []
      discarded = nil
      ActiveRecord.stub(:after_all_transactions_commit, ->(&callback) { callbacks << callback }) do
        discarded = DiscardAttachment.call(
          attachment:,
          actor: @actor,
          catalog: registry
        )
      end
      assert_predicate discarded, :success?
      assert_equal false, discarded.value.fetch(:idempotent)
      assert_equal 1, callbacks.length
      refute enqueued_jobs.any? { |job| job[:job] == Maintenance::CleanupForumUploadsJob }
      assert_enqueued_jobs 1, only: Maintenance::CleanupForumUploadsJob do
        callbacks.each(&:call)
      end

      assert_equal "purge_pending", attachment.reload.state
      assert_equal "cleanup_pending", attachment.upload_record.reload.status
      assert Community::Upload.cleanup_due(Time.current).exists?(attachment.upload_record.id)
      assert_equal 1, attachment.events.where(event_type: "discarded").count
      assert AuditLog.exists?(
        action: "secure_evidence.discarded",
        resource_public_id: attachment.public_id
      )

      replay_callbacks = []
      replay = nil
      ActiveRecord.stub(:after_all_transactions_commit, ->(&callback) { replay_callbacks << callback }) do
        replay = DiscardAttachment.call(
          attachment:,
          actor: @actor,
          catalog: registry
        )
      end
      assert_predicate replay, :success?
      assert_equal true, replay.value.fetch(:idempotent)
      assert_equal 1, replay_callbacks.length
      assert_equal 1, attachment.events.where(event_type: "discarded").count

      replacement = create_attachment(
        file: uploaded_file("replacement"),
        registry:,
        key: "evidence-discard-0002"
      )
      assert_predicate replacement, :success?
    end

    test "discard fails closed for another uploader linked evidence and an unregistered callback" do
      attachment = create_attachment(
        file: uploaded_file("private draft"),
        key: "evidence-discard-denied-1"
      ).value.fetch(:attachment)
      another_user = create_user

      non_owner = DiscardAttachment.call(
        attachment:,
        actor: another_user,
        catalog: @registry
      )
      assert_predicate non_owner, :failure?
      assert_equal "secure_evidence_discard_unavailable", non_owner.code

      @attachment_linked = true
      linked = DiscardAttachment.call(
        attachment:,
        actor: @actor,
        catalog: @registry
      )
      assert_predicate linked, :failure?
      assert_equal "secure_evidence_discard_unavailable", linked.code

      no_callback = build_registry(discard_authorizer: nil)
      @attachment_linked = false
      unregistered = DiscardAttachment.call(
        attachment:,
        actor: @actor,
        catalog: no_callback
      )
      assert_predicate unregistered, :failure?
      assert_equal "secure_evidence_discard_unavailable", unregistered.code
      assert_equal "pending", attachment.reload.state
    end

    test "late scan completion cannot revive a discarded attachment or cleanup upload" do
      attachment = create_attachment(
        file: uploaded_file("racing scan"),
        key: "evidence-discard-race-1"
      ).value.fetch(:attachment)
      scanner_result = Community::AttachmentMalwareScanner::Result.new(
        status: :clean,
        scanner: "race_scanner",
        code: "clean",
        error_message: nil
      )
      scanner = lambda do |blob:|
        assert blob
        discard = DiscardAttachment.call(
          attachment:,
          actor: @actor,
          catalog: @registry
        )
        assert_predicate discard, :success?
        scanner_result
      end

      result = Community::ScanPostAttachment.call(
        upload: attachment.upload_record,
        scanner:,
        now: Time.current
      )

      assert_predicate result, :success?
      assert_equal "stale_scan_result", result.value.fetch(:skipped)
      assert_equal "purge_pending", attachment.reload.state
      assert_equal "cleanup_pending", attachment.upload_record.reload.status
      refute attachment.events.where(event_type: "scan_clean").exists?

      claimed_again = Community::ScanPostAttachment.call(
        upload: attachment.upload_record,
        scanner: clean_scanner,
        force: true,
        now: 1.minute.from_now
      )
      assert_predicate claimed_again, :success?
      assert_equal "cleanup_started", claimed_again.value.fetch(:skipped)
    end

    test "discard cleanup removes the blob but preserves immutable metadata and replay" do
      attachment = create_attachment(
        file: uploaded_file("discard and retain"),
        key: "evidence-discard-retain-1"
      ).value.fetch(:attachment)
      blob_id = attachment.blob.id
      metadata = attachment.attributes.slice(
        "public_id",
        "uploader_id",
        "subject_key",
        "subject_id",
        "filename",
        "sha256"
      )

      discarded = DiscardAttachment.call(
        attachment:,
        actor: @actor,
        catalog: @registry
      )
      assert_predicate discarded, :success?
      cleanup = Community::CleanupUpload.call(
        upload: attachment.upload_record,
        now: Time.current
      )

      assert_predicate cleanup, :success?
      assert_equal "purged", attachment.reload.state
      assert_equal metadata, attachment.attributes.slice(*metadata.keys)
      refute ActiveStorage::Blob.exists?(blob_id)
      assert_equal %w[created upload_stored discarded purged],
        attachment.events.timeline.pluck(:event_type)

      replay = DiscardAttachment.call(
        attachment:,
        actor: @actor,
        catalog: @registry
      )
      assert_predicate replay, :success?
      assert_equal true, replay.value.fetch(:idempotent)
    end

    test "duplicate cleanup claims wait for the active worker and stale claims remain recoverable" do
      attachment = create_attachment(
        file: uploaded_file("single cleanup worker"),
        key: "evidence-discard-worker-1"
      ).value.fetch(:attachment)
      DiscardAttachment.call(attachment:, actor: @actor, catalog: @registry)
      upload = attachment.upload_record
      upload.update!(cleanup_started_at: Time.current)

      duplicate = Community::CleanupUpload.call(upload:, now: Time.current)
      assert_predicate duplicate, :success?
      assert_equal "not_due", duplicate.value.fetch(:skipped)
      assert attachment.blob.present?

      upload.update!(cleanup_started_at: 31.minutes.ago)
      recovered = Community::CleanupUpload.call(upload:, now: Time.current)
      assert_predicate recovered, :success?
      assert_equal "purged", attachment.reload.state
    end

    test "discard replay repairs cleaned upload metadata left in purge pending" do
      attachment = create_attachment(
        file: uploaded_file("repair metadata"),
        key: "evidence-discard-repair-1"
      ).value.fetch(:attachment)
      DiscardAttachment.call(attachment:, actor: @actor, catalog: @registry)
      upload = attachment.upload_record
      blob = upload.blob
      blob.purge
      cleaned_at = 1.minute.from_now
      upload.update!(
        status: "cleaned",
        blob: nil,
        expires_at: nil,
        cleanup_started_at: nil,
        cleaned_at:
      )

      replay = DiscardAttachment.call(
        attachment:,
        actor: @actor,
        catalog: @registry,
        now: cleaned_at
      )

      assert_predicate replay, :success?
      assert_equal true, replay.value.fetch(:idempotent)
      assert_equal "purged", attachment.reload.state
      assert_equal cleaned_at.to_i, attachment.purged_at.to_i
      assert_equal 1, attachment.events.where(event_type: "purged").count
    end

    test "subject limits cannot widen the site attachment size limit" do
      SiteSetting.set("forum.attachments.max_size_mb", "1")
      registry = build_registry(max_file_bytes: 2.megabytes)

      result = create_attachment(
        file: uploaded_file("x" * (1.megabyte + 1)),
        registry:,
        key: "evidence-site-limit-1"
      )

      assert_predicate result, :failure?
      assert_equal "attachment_too_large", result.code
      assert_equal 0, Attachment.where(uploader: @actor).count
    end

    test "scan stays fail closed until clean and revoked authorization blocks download" do
      attachment = create_attachment(file: uploaded_file("clean evidence")).value.fetch(:attachment)

      refute AttachmentAccess.download_allowed?(attachment, actor: @actor, catalog: @registry)
      scan = Community::ScanPostAttachment.call(
        upload: attachment.upload_record,
        scanner: clean_scanner,
        now: Time.current
      )

      assert_predicate scan, :success?
      assert_equal "available", attachment.reload.state
      assert_equal "linked", attachment.upload_record.reload.status
      assert AttachmentAccess.download_allowed?(attachment, actor: @actor, catalog: @registry)
      assert_equal 1, attachment.events.where(event_type: "scan_clean").count

      @download_allowed = false
      refute AttachmentAccess.download_allowed?(attachment, actor: @actor, catalog: @registry)
    end

    test "infected and exhausted scanner errors quarantine without becoming downloadable" do
      infected = create_attachment(
        file: uploaded_file("infected payload"),
        key: "evidence-infected-1"
      ).value.fetch(:attachment)
      Community::ScanPostAttachment.call(
        upload: infected.upload_record,
        scanner: infected_scanner,
        now: Time.current
      )

      assert_equal "quarantined", infected.reload.state
      assert_equal "infected", infected.upload_record.reload.scan_status
      refute AttachmentAccess.download_allowed?(infected, actor: @actor, catalog: @registry)

      errored = create_attachment(
        file: uploaded_file("scanner failure"),
        key: "evidence-error-0001"
      ).value.fetch(:attachment)
      errored.upload_record.update!(scan_attempts: 4)
      result = Community::ScanPostAttachment.call(
        upload: errored.upload_record,
        scanner: error_scanner,
        now: Time.current
      )

      assert_predicate result, :failure?
      assert_equal "quarantined", errored.reload.state
      assert_equal "error", errored.upload_record.reload.scan_status
      assert_nil errored.upload_record.next_scan_at
    end

    test "retention scheduler rechecks policy and reuses managed cleanup while preserving metadata" do
      created_at = 3.days.ago
      @retention_period = 1.day
      attachment = create_attachment(
        file: uploaded_file("expired evidence"),
        key: "evidence-expired-1",
        now: created_at
      ).value.fetch(:attachment)
      Community::ScanPostAttachment.call(
        upload: attachment.upload_record,
        scanner: clean_scanner,
        now: created_at + 1.minute,
        force: true
      )
      blob_id = attachment.blob.id

      scheduled = PurgeAttachment.call(
        attachment:,
        catalog: @registry,
        now: Time.current
      )
      assert_predicate scheduled, :success?
      assert_equal "purge_pending", attachment.reload.state
      assert_equal "cleanup_pending", attachment.upload_record.reload.status

      cleanup = Community::CleanupUpload.call(
        upload: attachment.upload_record,
        now: Time.current
      )
      assert_predicate cleanup, :success?
      assert_equal "purged", attachment.reload.state
      assert attachment.purged_at
      assert_equal "expired evidence.txt", attachment.filename
      refute ActiveStorage::Blob.exists?(blob_id)
      assert_equal %w[created upload_stored scan_clean cleanup_scheduled purged],
        attachment.events.timeline.pluck(:event_type)
    end

    test "generic upload cleanup cannot bypass evidence retention" do
      attachment = create_attachment(file: uploaded_file("retained evidence")).value.fetch(:attachment)
      Community::ScanPostAttachment.call(
        upload: attachment.upload_record,
        scanner: infected_scanner,
        now: Time.current
      )
      attachment.upload_record.update!(expires_at: 1.minute.ago)

      result = Community::CleanupUpload.call(
        upload: attachment.upload_record,
        force: true,
        now: Time.current
      )

      assert_predicate result, :success?
      assert_equal "not_due", result.value.fetch(:skipped)
      assert attachment.blob.present?
      assert_equal "quarantined", attachment.reload.state
    end

    test "failed evidence blob cleanup remains retryable after retention approval" do
      created_at = 3.days.ago
      @retention_period = 1.day
      attachment = create_attachment(
        file: uploaded_file("retry cleanup evidence"),
        key: "evidence-cleanup-retry-1",
        now: created_at
      ).value.fetch(:attachment)
      scheduled = PurgeAttachment.call(
        attachment:,
        catalog: @registry,
        now: Time.current
      )
      assert_predicate scheduled, :success?

      blob = attachment.blob
      original_delete = ActiveStorage::Blob.instance_method(:delete)
      target_blob_id = blob.id
      ActiveStorage::Blob.define_method(:delete) do
        raise IOError, "storage unavailable" if id == target_blob_id

        original_delete.bind_call(self)
      end
      begin
        failed = Community::CleanupUpload.call(
          upload: attachment.upload_record,
          now: Time.current
        )
      ensure
        ActiveStorage::Blob.define_method(:delete, original_delete)
      end

      assert_predicate failed, :failure?
      assert_equal "cleanup_failed", attachment.upload_record.reload.status
      assert_equal "purge_pending", attachment.reload.state
      assert ActiveStorage::Blob.exists?(blob.id)

      retried = Community::CleanupUpload.call(
        upload: attachment.upload_record,
        now: 1.minute.from_now
      )
      assert_predicate retried, :success?
      assert_equal "purged", attachment.reload.state
      refute ActiveStorage::Blob.exists?(blob.id)
    end

    test "cleanup rechecks retention extensions and account holds fail closed" do
      created_at = 3.days.ago
      @retention_period = 1.day
      extended = create_attachment(
        file: uploaded_file("extension evidence"),
        key: "evidence-extension-1",
        now: created_at
      ).value.fetch(:attachment)
      @retention_period = 10.days

      extension_result = PurgeAttachment.call(
        attachment: extended,
        catalog: @registry,
        now: Time.current
      )
      assert_predicate extension_result, :success?
      assert extension_result.value.fetch(:retention_extended)
      assert_equal "pending", extended.reload.state
      assert_operator extended.retention_until, :>, Time.current
      assert_equal 1, extended.events.where(event_type: "retention_extended").count

      @retention_period = 1.day
      held = create_attachment(
        file: uploaded_file("held evidence"),
        key: "evidence-held-0001",
        now: created_at
      ).value.fetch(:attachment)
      DataGovernance::RetentionHold.create!(
        target: @actor,
        created_by: @actor,
        status: "active",
        reason: "Preserve evidence during investigation"
      )

      held_result = PurgeAttachment.call(
        attachment: held,
        catalog: @registry,
        now: Time.current
      )
      assert_predicate held_result, :failure?
      assert_equal "secure_evidence_retention_hold", held_result.code
      assert_equal "pending", held.reload.state
      assert held.blob.present?
    end

    test "identity export and closure contributors retain metadata without raw storage locators" do
      attachment = create_attachment(file: uploaded_file("identity evidence")).value.fetch(:attachment)
      context = ::Identity::DataExporting::Context.new(user: @actor, generated_at: Time.current)
      export = IdentityLifecycle::DataExportContributor.call(context:)
      record = export.documents.fetch("secure_evidence/attachments.json").first
      events = export.documents.fetch("secure_evidence/attachment-events.json").each_record.to_a

      assert_equal attachment.public_id, record.fetch("public_id")
      assert_equal attachment.sha256, record.fetch("sha256")
      assert events.any? { |event| event.fetch("attachment_public_id") == attachment.public_id }
      refute record.key?("blob_key")
      refute record.key?("download_url")
      refute record.key?("scanner")
      refute record.key?("scan_result_code")

      closure_context = ::Identity::AccountClosure::Context.new(
        user: @actor,
        closure_mode: "delete_content",
        reason: "test",
        at: Time.current
      )
      preflight = IdentityLifecycle::AccountClosureContributor.preflight(context: closure_context)
      execution = IdentityLifecycle::AccountClosureContributor.execute(
        context: closure_context,
        preflight:
      )
      assert_predicate preflight, :ready?
      assert_predicate execution, :completed?
      assert_equal "stable_public_id_snapshot", execution.details.fetch("uploader_identity")
    end

    test "database trigger rejects event update and delete bypasses" do
      attachment = create_attachment(file: uploaded_file("immutable evidence")).value.fetch(:attachment)
      event = attachment.events.first

      assert_raises(ActiveRecord::StatementInvalid) do
        AttachmentEvent.transaction(requires_new: true) do
          AttachmentEvent.where(id: event.id).update_all(event_type: "downloaded")
        end
      end
      assert_raises(ActiveRecord::StatementInvalid) do
        AttachmentEvent.transaction(requires_new: true) do
          AttachmentEvent.where(id: event.id).delete_all
        end
      end
      assert_raises(ActiveRecord::StatementInvalid) do
        Attachment.transaction(requires_new: true) do
          Attachment.where(id: attachment.id).delete_all
        end
      end
      assert_raises(ActiveRecord::StatementInvalid) do
        Attachment.transaction(requires_new: true) do
          Attachment.where(id: attachment.id).update_all(filename: "tampered.txt")
        end
      end
      assert_raises(ActiveRecord::StatementInvalid) do
        Attachment.transaction(requires_new: true) do
          Attachment.where(id: attachment.id).update_all(state: "available", scanned_at: nil)
        end
      end
      assert_raises(ActiveRecord::StatementInvalid) do
        Attachment.transaction(requires_new: true) do
          Attachment.where(id: attachment.id).update_all(scanned_at: attachment.created_at - 1.minute)
        end
      end
      assert_raises(ActiveRecord::StatementInvalid) do
        Community::Upload.transaction(requires_new: true) do
          Community::Upload.where(id: attachment.upload_record.id).update_all(kind: "post_attachment")
        end
      end
      assert_equal "created", event.reload.event_type
      assert Attachment.exists?(attachment.id)
      assert_equal "expired evidence.txt", attachment.reload.filename
    end

    test "event and platform audit are atomic even without an outer transaction" do
      attachment = create_attachment(file: uploaded_file("atomic audit evidence"))
        .value.fetch(:attachment)
      key = "evidence:test-audit-failure:#{attachment.id}"
      audit_failure = ServiceResult.failure(error: "audit_unavailable")

      Administration::AuditLogger.stub(:call, audit_failure) do
        assert_raises(EventRecorder::AuditFailure) do
          EventRecorder.record!(
            attachment:,
            actor: @actor,
            event_type: "downloaded",
            idempotency_key: key
          )
        end
      end

      refute AttachmentEvent.exists?(idempotency_key: key)
      refute AuditLog.exists?(request_id: key)

      replay_key = "evidence:test-audit-replay:#{attachment.id}"
      first = EventRecorder.record!(
        attachment:,
        actor: @actor,
        event_type: "downloaded",
        idempotency_key: replay_key,
        metadata: { download_request_id: "same-request" }
      )
      replay = EventRecorder.record!(
        attachment:,
        actor: @actor,
        event_type: "downloaded",
        idempotency_key: replay_key,
        metadata: { download_request_id: "same-request" }
      )
      assert_equal first, replay
      assert_raises(ArgumentError) do
        EventRecorder.record!(
          attachment:,
          actor: @actor,
          event_type: "downloaded",
          idempotency_key: replay_key,
          metadata: { download_request_id: "different-request" }
        )
      end
    end

    private

    def build_registry(
      max_files: 4,
      max_file_bytes: 1.megabyte,
      max_total_bytes: 4.megabytes,
      discard_authorizer: :default
    )
      registry = SubjectRegistry.new
      registry.register(
        key: "test.evidence_case",
        model_name: "User",
        resolver: ->(public_id:) { User.find_by(public_id:) },
        upload_authorizer: ->(actor:, subject:) { actor.id == subject.id },
        download_authorizer: ->(actor:, subject:, attachment:) {
          @download_allowed && actor.id == subject.id && attachment.subject_id == subject.id
        },
        discard_authorizer: discard_authorizer == :default ? ->(actor:, subject:, attachment:) {
          @discard_allowed &&
            !@attachment_linked &&
            actor.id == subject.id &&
            attachment.subject_id == subject.id
        } : discard_authorizer,
        retention: ->(subject:, attached_at:) {
          attached_at + @retention_period if subject.persisted?
        },
        max_files:,
        max_file_bytes:,
        max_total_bytes:,
        allowed_extensions: %w[txt]
      )
      registry.freeze!
    end

    def create_attachment(file:, registry: @registry, key: "evidence-request-0001", now: Time.current)
      CreateAttachment.call(
        actor: @actor,
        subject_key: "test.evidence_case",
        subject_public_id: @actor.public_id,
        file:,
        idempotency_key: key,
        catalog: registry,
        now:
      )
    end

    def uploaded_file(content, filename: "expired evidence.txt")
      tempfile = Tempfile.new([ "evidence", ".txt" ])
      tempfile.binmode
      tempfile.write(content)
      tempfile.rewind
      @temporary_files << tempfile
      ActionDispatch::Http::UploadedFile.new(
        tempfile:,
        filename:,
        type: "text/plain"
      )
    end

    def clean_scanner
      result = Community::AttachmentMalwareScanner::Result.new(
        status: :clean,
        scanner: "test_scanner",
        code: "clean",
        error_message: nil
      )
      ->(blob:) { result if blob }
    end

    def infected_scanner
      result = Community::AttachmentMalwareScanner::Result.new(
        status: :infected,
        scanner: "test_scanner",
        code: "malware_detected",
        error_message: nil
      )
      ->(blob:) { result if blob }
    end

    def error_scanner
      result = Community::AttachmentMalwareScanner::Result.new(
        status: :error,
        scanner: "test_scanner",
        code: "scanner_timeout",
        error_message: "Timeout"
      )
      ->(blob:) { result if blob }
    end
  end
end
