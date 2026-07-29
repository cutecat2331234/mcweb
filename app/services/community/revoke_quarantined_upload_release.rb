# frozen_string_literal: true

module Community
  class RevokeQuarantinedUploadRelease < ApplicationService
    PERMISSION = ReleaseQuarantinedUpload::PERMISSION
    MIN_REASON_LENGTH = ReleaseQuarantinedUpload::MIN_REASON_LENGTH
    MAX_REASON_LENGTH = ReleaseQuarantinedUpload::MAX_REASON_LENGTH

    def initialize(upload:, actor:, confirmation:, reason:, ip_address: nil,
                   user_agent: nil, now: Time.current)
      @upload = upload
      @actor = actor
      @confirmation = confirmation.to_s.strip
      @reason = reason.to_s.strip
      @ip_address = ip_address
      @user_agent = user_agent.to_s.first(500).presence
      @now = now
    end

    def call
      return failure("forbidden") unless @actor&.permission?(PERMISSION)
      return failure("invalid_review_reason") unless valid_reason?
      return failure("confirmation_mismatch") unless confirmation_matches?

      revoked_upload = nil
      Community::Upload.transaction do
        upload = Community::Upload.lock.find(@upload.id)
        return failure("not_allowed") unless revocable?(upload)
        return failure("confirmation_mismatch") unless confirmation_matches?(upload)

        before_state = {
          scan_status: upload.scan_status,
          scan_result_code: upload.scan_result_code,
          manual_review_status: upload.manual_review_status,
          manual_review_version: upload.manual_review_version,
          manual_reviewed_at: upload.manual_reviewed_at&.iso8601,
          manual_reviewed_by_id: upload.manual_reviewed_by_id
        }

        upload.update!(
          scan_status: "infected",
          scanner: "manual_review",
          scan_result_code: "manual_release_revoked",
          scan_error_message: nil,
          scan_started_at: nil,
          next_scan_at: nil,
          scanned_at: @now,
          quarantined_at: @now,
          manual_review_status: "revoked",
          manual_review_version: upload.manual_review_version + 1,
          manual_review_revoked_at: @now,
          manual_review_revoked_by: @actor
        )

        Administration::AuditLogger.call(
          actor: @actor,
          action: "admin.forum_attachment_quarantine_release_revoked",
          resource: upload,
          reason: @reason,
          ip_address: @ip_address,
          user_agent: @user_agent,
          metadata: {
            released_by_id: before_state.fetch(:manual_reviewed_by_id),
            released_at: before_state.fetch(:manual_reviewed_at),
            source_result_code: upload.manual_review_source_result_code,
            source_file_sha256: upload.manual_review_file_sha256
          },
          before_state: before_state,
          after_state: {
            scan_status: upload.scan_status,
            scan_result_code: upload.scan_result_code,
            manual_review_status: upload.manual_review_status,
            manual_review_version: upload.manual_review_version,
            quarantined_at: upload.quarantined_at&.iso8601
          }
        )
        revoked_upload = upload
      end

      ActiveSupport::Notifications.instrument(
        "community.attachment.quarantine_release_revoked",
        upload_id: revoked_upload.id,
        actor_id: @actor.id
      )
      ServiceResult.success(upload: revoked_upload)
    rescue ActiveRecord::RecordNotFound
      failure("not_allowed")
    rescue ActiveRecord::ActiveRecordError => error
      Rails.logger.error(
        "[Community::RevokeQuarantinedUploadRelease] persistence failed " \
        "upload_id=#{@upload.id} error=#{error.class}"
      )
      failure("failed")
    end

    def self.confirmation_for(upload)
      "REVOKE #{upload.public_id} v#{upload.manual_review_version}"
    end

    private

    def valid_reason?
      @reason.length.between?(MIN_REASON_LENGTH, MAX_REASON_LENGTH)
    end

    def confirmation_matches?(upload = @upload)
      expected = self.class.confirmation_for(upload)
      @confirmation.bytesize == expected.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(@confirmation, expected)
    end

    def revocable?(upload)
      upload.kind_post_attachment? &&
        !upload.status_cleaned? &&
        upload.scan_status_clean? &&
        upload.manual_review_status_released? &&
        upload.active_storage_blob_id.present?
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
