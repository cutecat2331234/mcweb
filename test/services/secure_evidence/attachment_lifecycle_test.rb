# frozen_string_literal: true

require "test_helper"
require "tempfile"

module SecureEvidence
  class AttachmentLifecycleTest < ActiveSupport::TestCase
    setup do
      @actor = create_user
      @download_allowed = true
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
      assert AuditLog.exists?(action: "secure_evidence.created", resource_public_id: attachment.public_id)
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
      assert_equal %w[created scan_clean cleanup_scheduled purged],
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
      original_purge = ActiveStorage::Blob.instance_method(:purge)
      target_blob_id = blob.id
      ActiveStorage::Blob.define_method(:purge) do
        raise IOError, "storage unavailable" if id == target_blob_id

        original_purge.bind_call(self)
      end
      begin
        failed = Community::CleanupUpload.call(
          upload: attachment.upload_record,
          now: Time.current
        )
      ensure
        ActiveStorage::Blob.define_method(:purge, original_purge)
      end

      assert_predicate failed, :failure?
      assert_equal "cleanup_failed", attachment.upload_record.reload.status
      assert_equal "purge_pending", attachment.reload.state

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

      assert_equal attachment.public_id, record.fetch("public_id")
      assert_equal attachment.sha256, record.fetch("sha256")
      refute record.key?("blob_key")
      refute record.key?("download_url")

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
      max_total_bytes: 4.megabytes
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
