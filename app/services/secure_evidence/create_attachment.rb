# frozen_string_literal: true

module SecureEvidence
  class CreateAttachment < ApplicationService
    IDEMPOTENCY_PATTERN = /\A[A-Za-z0-9:_-]{8,100}\z/

    def initialize(
      actor:,
      subject_key:,
      subject_public_id:,
      file:,
      idempotency_key:,
      catalog: SubjectCatalog,
      now: Time.current
    )
      @actor = actor
      @subject_key = subject_key.to_s
      @subject_public_id = subject_public_id.to_s.strip
      @file = file
      @idempotency_key = idempotency_key.to_s.strip
      @catalog = catalog
      @now = now
    end

    def call
      caller_connection = ApplicationRecord.connection_pool.active_connection
      entry = @catalog.entry_for_key(@subject_key)
      return failure("secure_evidence_subject_unavailable") unless entry
      return failure("secure_evidence_idempotency_key_invalid") unless valid_idempotency_key?
      return failure("upload_file_required") unless @file

      subject = SubjectPolicy.resolve(entry:, public_id: @subject_public_id)
      return failure("secure_evidence_subject_unavailable") unless subject
      unless AttachmentAccess.upload_allowed?(entry:, actor: @actor, subject:)
        return failure("secure_evidence_subject_unavailable")
      end

      filename = safe_filename(@file.original_filename)
      return failure("invalid_filename") if filename.blank?

      max_file_bytes = [
        entry.max_file_bytes,
        Community::AllowedAttachmentTypes.max_size
      ].min
      inspection = Community::AllowedAttachmentTypes.inspect_file(
        filename:,
        io: @file,
        allowed_extensions: entry.allowed_extensions,
        max_bytes: max_file_bytes
      )
      return file_inspection_failure(max_file_bytes, inspection) unless inspection.success?

      sha256 = Digest::SHA256.hexdigest(inspection.payload)
      fingerprint = request_fingerprint(
        subject_id: subject.id,
        filename:,
        byte_size: inspection.byte_size,
        sha256:
      )
      reservation = reserve_attempt(
        entry:,
        subject:,
        filename:,
        inspection:,
        sha256:,
        fingerprint:
      )
      if reservation.failure?
        enqueue_retry_cleanup(reservation)
        return reservation
      end

      reserved = reservation.value
      attachment = reserved.fetch(:attachment)
      unless reserved.fetch(:upload_required)
        return ServiceResult.success(attachment:, idempotent: true)
      end

      release_service_database_lease!(caller_connection)
      stored = StoreAttachmentUpload.call(
        attachment:,
        upload: reserved.fetch(:upload),
        payload: inspection.payload,
        filename:,
        content_type: inspection.content_type,
        at: @now
      )
      return stored if stored.failure?

      upload = stored.value.fetch(:upload)
      enqueue_scan(upload)
      ServiceResult.success(
        attachment: stored.value.fetch(:attachment),
        idempotent: reserved.fetch(:idempotent)
      )
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    rescue StandardError => error
      Rails.logger.error("[SecureEvidence::CreateAttachment] failed error=#{error.class}")
      failure("secure_evidence_creation_failed")
    end

    private

    def reserve_attempt(entry:, subject:, filename:, inspection:, sha256:, fingerprint:)
      result = nil

      Attachment.transaction do
        Community::UploadQuota.acquire_admission_lock!
        subject.lock!
        unless AttachmentAccess.upload_allowed?(entry:, actor: @actor, subject:)
          result = failure("secure_evidence_subject_unavailable")
          next
        end

        existing = idempotent_record(subject)
        if existing
          result = reserve_existing_attempt(
            entry:,
            subject:,
            existing:,
            fingerprint:,
            requested_bytes: inspection.byte_size
          )
          next
        end

        limit_failure = subject_limit_failure(
          entry:,
          subject:,
          requested_bytes: inspection.byte_size
        )
        if limit_failure
          result = limit_failure
          next
        end

        retention_until = SubjectPolicy.retention_until(
          entry:,
          subject:,
          attached_at: @now
        )
        unless retention_until
          result = failure("secure_evidence_retention_invalid")
          next
        end

        quota = reserve_upload_quota(inspection.byte_size)
        if quota.failure?
          result = quota
          next
        end

        upload = quota.value
        attachment = Attachment.create!(
          uploader: @actor,
          uploader_public_id_snapshot: @actor.public_id,
          subject_key: entry.key,
          subject_id: subject.id,
          subject_public_id: subject.public_id.to_s,
          idempotency_key: @idempotency_key,
          request_fingerprint: fingerprint,
          filename:,
          content_type: inspection.content_type,
          byte_size: inspection.byte_size,
          sha256:,
          state: "uploading",
          retention_until:,
          created_at: @now,
          updated_at: @now
        )
        upload.update!(secure_evidence_attachment: attachment)
        EventRecorder.record!(
          attachment:,
          actor: @actor,
          event_type: "created",
          idempotency_key: "evidence:create:#{attachment.id}:#{@idempotency_key}",
          metadata: { retention_until: retention_until.iso8601(6) },
          at: @now
        )
        result = ServiceResult.success(
          attachment:,
          upload:,
          idempotent: false,
          upload_required: true
        )
      end

      result || failure("secure_evidence_creation_failed")
    end

    def reserve_existing_attempt(entry:, subject:, existing:, fingerprint:, requested_bytes:)
      return replay_result(existing, fingerprint) unless existing.state_upload_failed?
      return failure("secure_evidence_idempotency_conflict") unless secure_match?(
        existing.request_fingerprint,
        fingerprint
      )

      upload = Community::Upload.lock.find_by(
        secure_evidence_attachment_id: existing.id
      )
      return failure("secure_evidence_upload_missing") unless upload

      existing.lock!
      return replay_result(existing, fingerprint) unless existing.state_upload_failed?
      unless upload.status_cleaned? && upload.active_storage_blob_id.nil?
        return failure(
          "secure_evidence_upload_retry_pending",
          value: {
            attachment: existing,
            retryable: true,
            cleanup_upload_id: upload.id
          }
        )
      end

      limit_failure = subject_limit_failure(
        entry:,
        subject:,
        requested_bytes:
      )
      return limit_failure if limit_failure

      quota = reserve_upload_quota(requested_bytes, reuse_upload: upload)
      return quota if quota.failure?

      retry_upload = quota.value
      SyncUploadResult.retried!(
        attachment: existing,
        upload: retry_upload,
        at: @now
      )
      ServiceResult.success(
        attachment: existing,
        upload: retry_upload,
        idempotent: true,
        upload_required: true
      )
    end

    def reserve_upload_quota(byte_size, reuse_upload: nil)
      Community::UploadQuota.call(
        user: @actor,
        kind: :secure_evidence_attachment,
        byte_size:,
        reuse_upload:
      )
    end

    def release_service_database_lease!(caller_connection)
      return if caller_connection

      pool = ApplicationRecord.connection_pool
      connection = pool.active_connection
      return unless connection

      if connection.transaction_open?
        raise ActiveRecord::ActiveRecordError,
          "secure_evidence_remote_upload_transaction_open"
      end

      pool.release_connection
    end

    def failure(code, value: nil)
      ServiceResult.failure(error: code, code:, value:)
    end

    def valid_idempotency_key?
      @idempotency_key.match?(IDEMPOTENCY_PATTERN)
    end

    def safe_filename(name)
      base = File.basename(name.to_s)
      base.gsub(/[^\w.\-()\[\] ]+/u, "_").strip.first(180)
    end

    def file_inspection_failure(max_file_bytes, inspection)
      if inspection.too_large?
        max = ActiveSupport::NumberHelper.number_to_human_size(max_file_bytes)
        return ServiceResult.failure(
          error: I18n.t("mcweb.services.errors.attachment_too_large", max:),
          code: "attachment_too_large"
        )
      end

      failure("unsupported_attachment_type")
    end

    def request_fingerprint(subject_id:, filename:, byte_size:, sha256:)
      Digest::SHA256.hexdigest(
        JSON.generate(
          subject_key: @subject_key,
          subject_id:,
          filename:,
          byte_size:,
          sha256:
        )
      )
    end

    def idempotent_record(subject)
      Attachment.find_by(
        uploader: @actor,
        subject_key: @subject_key,
        subject_id: subject.id,
        idempotency_key: @idempotency_key
      )
    end

    def replay_result(existing, fingerprint)
      return failure("secure_evidence_idempotency_conflict") unless secure_match?(
        existing.request_fingerprint,
        fingerprint
      )

      ServiceResult.success(
        attachment: existing,
        idempotent: true,
        upload_required: false
      )
    end

    def subject_limit_failure(entry:, subject:, requested_bytes:)
      relation = Attachment.left_joins(:upload_record).where(
        subject_key: entry.key,
        subject_id: subject.id
      ).where(
        "(secure_evidence_attachments.state IN (?) OR " \
        "(secure_evidence_attachments.state = 'upload_failed' AND " \
        "forum_uploads.status <> 'cleaned'))",
        Attachment::ACTIVE_STATES
      )
      return failure("secure_evidence_file_limit_exceeded") if relation.count >= entry.max_files
      if relation.sum(:byte_size) + requested_bytes > entry.max_total_bytes
        return failure("secure_evidence_total_size_exceeded")
      end

      nil
    end

    def secure_match?(left, right)
      left = left.to_s
      right = right.to_s
      left.bytesize == right.bytesize && ActiveSupport::SecurityUtils.secure_compare(left, right)
    end

    def enqueue_scan(upload)
      Community::ScanPostAttachmentJob.perform_later(upload_id: upload.id)
    rescue StandardError => error
      Rails.logger.error(
        "[SecureEvidence::CreateAttachment] scan scheduling failed " \
        "upload_id=#{upload.id} error=#{error.class}"
      )
    end

    def enqueue_retry_cleanup(result)
      value = result.value
      return unless value.is_a?(Hash)

      upload_id = value[:cleanup_upload_id]
      return unless upload_id

      Maintenance::CleanupForumUploadsJob.perform_later(upload_id:)
    rescue StandardError => error
      Rails.logger.error(
        "[SecureEvidence::CreateAttachment] retry cleanup scheduling failed " \
        "upload_id=#{upload_id} error=#{error.class}"
      )
    end
  end
end
