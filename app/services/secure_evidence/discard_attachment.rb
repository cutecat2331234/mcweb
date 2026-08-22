# frozen_string_literal: true

module SecureEvidence
  class DiscardAttachment < ApplicationService
    def initialize(attachment:, actor:, catalog: SubjectCatalog, now: Time.current)
      @attachment = attachment
      @actor = actor
      @catalog = catalog
      @now = now
    end

    def call
      return unavailable unless @attachment&.persisted? && @actor&.persisted?

      result = nil
      upload_id = nil

      Attachment.transaction do
        upload = Community::Upload.find_by(
          secure_evidence_attachment_id: @attachment.id
        )
        unless upload
          result = failure("secure_evidence_upload_missing")
          next
        end

        upload.lock!
        attachment = Attachment.lock.find_by(id: @attachment.id)
        unless attachment && valid_upload_owner?(upload, attachment)
          result = unavailable
          next
        end
        unless AttachmentAccess.discard_allowed?(attachment, actor: @actor, catalog: @catalog)
          result = unavailable
          next
        end

        @attachment = attachment
        if attachment.state_purged?
          result = success(idempotent: true)
          next
        end
        if attachment.state_purge_pending?
          if upload.status_cleaned?
            @attachment = SyncCleanupResult.purged!(
              attachment_id: attachment.id,
              upload:,
              at: upload.cleaned_at || @now
            )
          else
            upload_id = recover_cleanup_schedule(upload)
          end
          result = success(idempotent: true)
          next
        end

        attachment.update!(state: "purge_pending")
        upload.schedule_cleanup!(at: @now)
        EventRecorder.record!(
          attachment:,
          actor: @actor,
          event_type: "discarded",
          idempotency_key: "evidence:discarded:#{attachment.id}",
          at: @now
        )
        upload_id = upload.id
        result = success(idempotent: false)
      end

      enqueue_cleanup_after_commit(upload_id) if upload_id
      result || failure("secure_evidence_discard_failed")
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    rescue StandardError => error
      Rails.logger.error(
        "[SecureEvidence::DiscardAttachment] failed " \
        "attachment_id=#{@attachment&.id} error=#{error.class}"
      )
      failure("secure_evidence_discard_failed")
    end

    private

    def valid_upload_owner?(upload, attachment)
      upload.kind_secure_evidence_attachment? &&
        upload.user_id == @actor.id &&
        attachment.uploader_id == @actor.id
    end

    def recover_cleanup_schedule(upload)
      return upload.id if upload.status_cleanup_pending?

      upload.schedule_cleanup!(at: @now)
      upload.id
    end

    def enqueue_cleanup_after_commit(upload_id)
      ActiveRecord.after_all_transactions_commit do
        job = Maintenance::CleanupForumUploadsJob.perform_later(upload_id:)
        unless job&.successfully_enqueued?
          raise ActiveJob::EnqueueError, "secure evidence cleanup enqueue rejected"
        end
      rescue StandardError => error
        Rails.logger.error(
          "[SecureEvidence::DiscardAttachment] cleanup scheduling deferred " \
          "upload_id=#{upload_id} error=#{error.class}"
        )
      end
    end

    def success(idempotent:)
      ServiceResult.success(attachment: @attachment, idempotent:)
    end

    def unavailable
      failure("secure_evidence_discard_unavailable")
    end

    def failure(code)
      ServiceResult.failure(error: code, code:)
    end
  end
end
