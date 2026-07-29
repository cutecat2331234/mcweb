# frozen_string_literal: true

module Community
  # Records an explicit, privileged false-positive decision for a quarantined
  # attachment. The upload is never released by changing a flag in isolation:
  # permission, typed confirmation, review reason, state transition, and the
  # immutable audit record succeed or fail in one database transaction.
  class ReleaseQuarantinedUpload < ApplicationService
    PERMISSION = "forum.attachments.security.release"
    MIN_REASON_LENGTH = 12
    MAX_REASON_LENGTH = 1_000
    RELEASE_RETENTION = 24.hours
    RELEASABLE_RESULT_CODES = %w[malware_detected].freeze

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
      return failure("not_allowed") if @upload.user_id == @actor.id

      evidence = inspect_candidate
      return failure("not_allowed") unless evidence

      released_upload = nil

      Community::Upload.transaction do
        upload = Community::Upload.lock.find(@upload.id)
        return failure("not_allowed") unless releasable?(upload, evidence)

        before_state = {
          scan_status: upload.scan_status,
          scan_result_code: upload.scan_result_code,
          scanner: upload.scanner,
          quarantined_at: upload.quarantined_at&.iso8601,
          expires_at: upload.expires_at&.iso8601
        }
        upload.update!(
          scan_status: "clean",
          scan_started_at: nil,
          next_scan_at: nil,
          scanned_at: @now,
          quarantined_at: nil,
          expires_at: released_expiry(upload),
          scanner: "manual_review",
          scan_result_code: "manual_false_positive",
          scan_error_message: nil,
          manual_review_status: "released",
          manual_review_version: upload.manual_review_version + 1,
          manual_reviewed_at: @now,
          manual_reviewed_by: @actor,
          manual_review_source_result_code: before_state.fetch(:scan_result_code),
          manual_review_file_sha256: evidence.fetch(:file_sha256),
          manual_review_revoked_at: nil,
          manual_review_revoked_by: nil
        )

        Administration::AuditLogger.call(
          actor: @actor,
          action: "admin.forum_attachment_quarantine_released",
          resource: upload,
          reason: @reason,
          ip_address: @ip_address,
          user_agent: @user_agent,
          metadata: {
            original_scanner: before_state.fetch(:scanner),
            original_result_code: before_state.fetch(:scan_result_code),
            file_sha256: evidence.fetch(:file_sha256),
            active_storage_checksum: evidence.fetch(:checksum),
            file_size: evidence.fetch(:byte_size),
            inspected_content_type: evidence.fetch(:content_type)
          },
          before_state: before_state,
          after_state: {
            scan_status: upload.scan_status,
            scan_result_code: upload.scan_result_code,
            scanner: upload.scanner,
            quarantined_at: upload.quarantined_at,
            manual_review_status: upload.manual_review_status,
            manual_review_version: upload.manual_review_version
          }
        )
        released_upload = upload
      end

      Mcweb::Events.publish_notification(
        "community.attachment.quarantine_released",
        upload_id: released_upload.id,
        actor_id: @actor.id
      )
      ServiceResult.success(upload: released_upload)
    rescue ActiveRecord::RecordNotFound
      failure("not_allowed")
    rescue ActiveRecord::ActiveRecordError => error
      Rails.logger.error(
        "[Community::ReleaseQuarantinedUpload] persistence failed " \
        "upload_id=#{@upload.id} error=#{error.class}"
      )
      failure("failed")
    end

    def self.confirmation_for(upload)
      "RELEASE #{upload.public_id}"
    end

    private

    def valid_reason?
      @reason.length.between?(MIN_REASON_LENGTH, MAX_REASON_LENGTH)
    end

    def confirmation_matches?
      expected = self.class.confirmation_for(@upload)
      @confirmation.bytesize == expected.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(@confirmation, expected)
    end

    def inspect_candidate
      upload = @upload.reload
      blob = upload.blob
      filename = upload.post_attachment&.filename.presence || blob&.filename&.to_s
      return unless blob && filename.present?

      inspection = nil
      file_sha256 = nil
      blob.open do |file|
        inspection = Community::AllowedAttachmentTypes.inspect_file(filename: filename, io: file)
        next unless inspection.success?

        file.rewind
        digest = Digest::SHA256.new
        loop do
          chunk = file.read(1.megabyte)
          break unless chunk

          digest.update(chunk)
        end
        file_sha256 = digest.hexdigest
      end
      return unless inspection.success?

      {
        blob_id: blob.id,
        checksum: blob.checksum.to_s,
        file_sha256: file_sha256,
        byte_size: inspection.byte_size,
        content_type: inspection.content_type
      }
    rescue ActiveStorage::IntegrityError, ActiveStorage::FileNotFoundError, Errno::ENOENT
      nil
    end

    def releasable?(upload, evidence)
      upload.kind_post_attachment? &&
        upload.user_id != @actor.id &&
        !upload.status_cleaned? &&
        upload.scan_status_infected? &&
        upload.manual_review_status_none? &&
        upload.scan_result_code.in?(RELEASABLE_RESULT_CODES) &&
        upload.active_storage_blob_id == evidence.fetch(:blob_id) &&
        upload.blob&.checksum.to_s == evidence.fetch(:checksum)
    end

    def released_expiry(upload)
      return nil if upload.status_linked?

      [ upload.expires_at, @now + RELEASE_RETENTION ].compact.max
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
