# frozen_string_literal: true

module SecureEvidence
  class PurgeAttachment < ApplicationService
    def initialize(attachment:, actor: nil, catalog: SubjectCatalog, now: Time.current)
      @attachment = attachment
      @actor = actor
      @catalog = catalog
      @now = now
    end

    def call
      result = nil
      upload_id = nil

      Attachment.transaction do
        upload = @attachment.upload_record
        unless upload
          result = failure("secure_evidence_upload_missing")
          next
        end

        upload.lock!
        @attachment.lock!
        if @attachment.state_purged?
          result = ServiceResult.success(attachment: @attachment, idempotent: true)
          next
        end
        if @attachment.state_purge_pending?
          result = ServiceResult.success(attachment: @attachment, idempotent: true)
          upload_id = upload.id
          next
        end

        eligibility = purge_eligibility
        if eligibility.failure?
          result = eligibility
          next
        end
        if eligibility.value[:retention_extended]
          result = ServiceResult.success(
            attachment: @attachment,
            idempotent: false,
            retention_extended: true
          )
          next
        end

        @attachment.update!(state: "purge_pending")
        upload.schedule_cleanup!(at: @now)
        EventRecorder.record!(
          attachment: @attachment,
          actor: @actor,
          event_type: "cleanup_scheduled",
          idempotency_key: "evidence:cleanup-scheduled:#{@attachment.id}:#{@attachment.retention_until.to_i}",
          metadata: { retention_until: @attachment.retention_until.iso8601(6) },
          at: @now
        )
        upload_id = upload.id
        result = ServiceResult.success(attachment: @attachment, idempotent: false)
      end

      enqueue_cleanup(upload_id) if upload_id
      result || failure("secure_evidence_cleanup_failed")
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    rescue StandardError => error
      Rails.logger.error(
        "[SecureEvidence::PurgeAttachment] failed " \
        "attachment_id=#{@attachment.id} error=#{error.class}"
      )
      failure("secure_evidence_cleanup_failed")
    end

    private

    def purge_eligibility
      return failure("secure_evidence_retention_active") if @attachment.retention_until > @now
      return failure("secure_evidence_retention_hold") if held?(@attachment) || held?(@attachment.uploader)

      entry = @catalog.entry_for_key(@attachment.subject_key)
      return failure("secure_evidence_subject_unavailable") unless entry

      subject = SubjectPolicy.resolve(entry:, public_id: @attachment.subject_public_id)
      return ServiceResult.success(retention_extended: false) unless subject
      return failure("secure_evidence_retention_hold") if held?(subject)

      resolved = SubjectPolicy.retention_until(entry:, subject:, attached_at: @attachment.created_at)
      return failure("secure_evidence_retention_invalid") unless resolved
      return ServiceResult.success(retention_extended: false) unless resolved > @attachment.retention_until

      previous = @attachment.retention_until
      @attachment.update!(retention_until: resolved)
      EventRecorder.record!(
        attachment: @attachment,
        actor: @actor,
        event_type: "retention_extended",
        idempotency_key: "evidence:retention:#{@attachment.id}:#{resolved.to_i}",
        metadata: {
          previous_retention_until: previous.iso8601(6),
          retention_until: resolved.iso8601(6)
        },
        at: @now
      )
      ServiceResult.success(retention_extended: true)
    end

    def held?(target)
      DataGovernance::RetentionHold.effective.exists?(target: target)
    end

    def enqueue_cleanup(upload_id)
      Maintenance::CleanupForumUploadsJob.perform_later(upload_id:)
    rescue StandardError => error
      Rails.logger.error(
        "[SecureEvidence::PurgeAttachment] cleanup scheduling deferred " \
        "upload_id=#{upload_id} error=#{error.class}"
      )
    end

    def failure(code)
      ServiceResult.failure(error: code, code:)
    end
  end
end
