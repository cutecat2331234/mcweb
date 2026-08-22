# frozen_string_literal: true

module SecureEvidence
  class CreateAttachment < ApplicationService
    ADVISORY_LOCK_ID = 7_804_261_559_014_332_187
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
      @upload = nil
    end

    def call
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
      result = nil

      Attachment.transaction do
        acquire_creation_lock!
        subject.lock!
        unless AttachmentAccess.upload_allowed?(entry:, actor: @actor, subject:)
          result = failure("secure_evidence_subject_unavailable")
          next
        end

        existing = idempotent_record(subject)
        if existing
          result = replay_result(existing, fingerprint)
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

        stored = Community::StoreUpload.call(
          user: @actor,
          kind: :secure_evidence_attachment,
          payload: inspection.payload,
          filename:,
          content_type: inspection.content_type
        )
        if stored.failure?
          result = stored
          next
        end

        @upload = stored.value.fetch(:upload)
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
          state: "pending",
          retention_until:,
          created_at: @now,
          updated_at: @now
        )
        @upload.update!(secure_evidence_attachment: attachment)
        EventRecorder.record!(
          attachment:,
          actor: @actor,
          event_type: "created",
          idempotency_key: "evidence:create:#{attachment.id}:#{@idempotency_key}",
          metadata: { retention_until: retention_until.iso8601(6) },
          at: @now
        )
        result = ServiceResult.success(attachment: attachment, idempotent: false)
      end

      enqueue_scan if result&.success? && !result.value.fetch(:idempotent)
      result || failure("secure_evidence_creation_failed")
    rescue ActiveRecord::RecordInvalid => error
      request_cleanup(error)
      ServiceResult.failure(errors: error.record.errors.to_hash)
    rescue StandardError => error
      request_cleanup(error)
      Rails.logger.error("[SecureEvidence::CreateAttachment] failed error=#{error.class}")
      failure("secure_evidence_creation_failed")
    end

    private

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

    def acquire_creation_lock!
      ApplicationRecord.connection.select_value(
        "SELECT pg_advisory_xact_lock(#{ADVISORY_LOCK_ID})::text"
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

      ServiceResult.success(attachment: existing, idempotent: true)
    end

    def subject_limit_failure(entry:, subject:, requested_bytes:)
      relation = Attachment.where(
        subject_key: entry.key,
        subject_id: subject.id
      ).where.not(state: "purged")
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

    def enqueue_scan
      Community::ScanPostAttachmentJob.perform_later(upload_id: @upload.id)
    rescue StandardError => error
      Rails.logger.error(
        "[SecureEvidence::CreateAttachment] scan scheduling failed " \
        "upload_id=#{@upload.id} error=#{error.class}"
      )
    end

    def request_cleanup(error)
      return unless @upload&.persisted?

      @upload.request_cleanup!(error:)
      Maintenance::CleanupForumUploadsJob.perform_later(upload_id: @upload.id)
    rescue StandardError => cleanup_error
      Rails.logger.error(
        "[SecureEvidence::CreateAttachment] cleanup scheduling failed " \
        "upload_id=#{@upload&.id} error=#{cleanup_error.class}"
      )
    end
  end
end
