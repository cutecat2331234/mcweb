# frozen_string_literal: true

module Community
  class ScanPostAttachment < ApplicationService
    DEFAULT_MAX_ATTEMPTS = 5
    DEFAULT_RETRY_SECONDS = 30
    DEFAULT_INFECTED_RETENTION_HOURS = 24
    DEFAULT_ERROR_RETENTION_HOURS = 168
    STALE_CLAIM_AFTER = 15.minutes

    def initialize(upload:, scanner: Community::AttachmentMalwareScanner, now: Time.current, force: false)
      @upload = upload
      @scanner = scanner
      @now = now
      @force = force
    end

    def call
      claim = nil
      claim = claim_scan
      return claim if claim.failure? || claim.value[:skipped]

      scan_result = @scanner.call(blob: claim.value.fetch(:blob))
      persist_result(scan_result, claim: claim.value)
    rescue StandardError => error
      persist_scanner_error(error, claim: claim&.success? ? claim.value : nil)
    end

    private

    def claim_scan
      snapshot = nil
      skipped = nil

      @upload.with_lock do
        unless @upload.kind_post_attachment?
          skipped = "not_downloadable_attachment"
          next
        end
        if terminal_scan_status?
          skipped = "scan_terminal"
          next
        end
        if !@force && scan_in_progress?
          skipped = "scan_in_progress"
          next
        end
        if !@force && @upload.next_scan_at&.>(@now)
          skipped = "scan_not_due"
          next
        end
        if !@force && @upload.scan_attempts >= max_attempts
          skipped = "scan_attempts_exhausted"
          next
        end

        blob = @upload.blob
        unless blob
          return ServiceResult.failure(
            error: "attachment_blob_missing",
            code: "attachment_blob_missing",
            value: { upload: @upload, retryable: false }
          )
        end

        @upload.update!(
          scan_status: "pending",
          scan_attempts: @upload.scan_attempts + 1,
          scan_started_at: @now,
          next_scan_at: nil,
          scanner: nil,
          scan_result_code: nil,
          scan_error_message: nil
        )
        snapshot = {
          blob: blob,
          scan_attempt: @upload.scan_attempts
        }
      end

      return ServiceResult.success(skipped: skipped, upload: @upload) if skipped

      ServiceResult.success(snapshot)
    end

    def scan_in_progress?
      @upload.scan_status_pending? &&
        @upload.scan_started_at.present? &&
        @upload.scan_started_at > (@now - STALE_CLAIM_AFTER)
    end

    def terminal_scan_status?
      return true if @upload.scan_status_infected?
      return false if developer_mode_scan_requires_verification?

      @upload.scan_status_clean?
    end

    def developer_mode_scan_requires_verification?
      @upload.developer_mode_scan_bypassed? &&
        !Mcweb::DeveloperMode.allow?(:skip_attachment_malware_scan)
    end

    def persist_result(result, claim:)
      return persist_clean(result, claim: claim) if result.clean?
      return persist_infected(result, claim: claim) if result.infected?

      persist_error_result(result, claim: claim)
    end

    def persist_clean(result, claim:)
      @upload.with_lock do
        return stale_result unless current_claim?(claim)

        @upload.update!(
          scan_status: "clean",
          scan_started_at: nil,
          next_scan_at: nil,
          scanned_at: @now,
          quarantined_at: nil,
          scanner: result.scanner,
          scan_result_code: result.code,
          scan_error_message: nil
        )
      end
      instrument("community.attachment.scan_clean")
      ServiceResult.success(upload: @upload, status: "clean")
    end

    def persist_infected(result, claim:)
      @upload.with_lock do
        return stale_result unless current_claim?(claim)

        @upload.update!(
          scan_status: "infected",
          scan_started_at: nil,
          next_scan_at: nil,
          scanned_at: @now,
          quarantined_at: @now,
          expires_at: @now + configured_hours(
            "forum.attachments.infected_retention_hours",
            DEFAULT_INFECTED_RETENTION_HOURS
          ).hours,
          scanner: result.scanner,
          scan_result_code: result.code,
          scan_error_message: nil
        )
      end
      instrument("community.attachment.scan_infected")
      ServiceResult.success(upload: @upload, status: "infected")
    end

    def persist_error_result(result, claim:)
      retryable = @upload.scan_attempts < max_attempts
      next_scan_at = retryable ? @now + retry_delay : nil

      @upload.with_lock do
        return stale_result unless current_claim?(claim)

        @upload.update!(
          scan_status: "error",
          scan_started_at: nil,
          next_scan_at: next_scan_at,
          scanned_at: @now,
          quarantined_at: retryable ? nil : @now,
          expires_at: retryable ? extended_pending_expiry(next_scan_at) : error_expiry,
          scanner: result.scanner,
          scan_result_code: result.code,
          scan_error_message: result.error_message.to_s.first(500).presence
        )
      end
      instrument(
        "community.attachment.scan_error",
        retryable: retryable,
        code: result.code
      )
      ServiceResult.failure(
        error: "attachment_scan_failed",
        code: "attachment_scan_failed",
        value: {
          upload: @upload,
          retryable: retryable,
          next_scan_at: next_scan_at
        }
      )
    end

    def persist_scanner_error(error, claim:)
      return unclaimed_error(error) unless claim

      result = Community::AttachmentMalwareScanner::Result.new(
        status: :error,
        scanner: "scanner",
        code: "scanner_internal_error",
        error_message: error.class.name
      )
      persist_error_result(result, claim: claim)
    rescue StandardError => record_error
      Rails.logger.error(
        "[Community::ScanPostAttachment] failed upload_id=#{@upload.id} " \
        "error=#{error.class} record_error=#{record_error.class}"
      )
      ServiceResult.failure(
        error: "attachment_scan_failed",
        code: "attachment_scan_failed",
        value: { upload: @upload, retryable: true }
      )
    end

    def current_claim?(claim)
      @upload.scan_status_pending? &&
        @upload.scan_attempts == claim.fetch(:scan_attempt)
    end

    def stale_result
      ServiceResult.success(
        skipped: "stale_scan_result",
        upload: @upload
      )
    end

    def unclaimed_error(error)
      Rails.logger.error(
        "[Community::ScanPostAttachment] failed before claim upload_id=#{@upload.id} " \
        "error=#{error.class}"
      )
      ServiceResult.failure(
        error: "attachment_scan_failed",
        code: "attachment_scan_failed",
        value: { upload: @upload, retryable: true }
      )
    end

    def extended_pending_expiry(next_scan_at)
      minimum = [ next_scan_at + 1.hour, error_expiry ].max
      [ @upload.expires_at, minimum ].compact.max
    end

    def error_expiry
      @now + configured_hours(
        "forum.attachments.scan_error_retention_hours",
        DEFAULT_ERROR_RETENTION_HOURS
      ).hours
    end

    def retry_delay
      base = configured_integer(
        "forum.attachments.scan_retry_seconds",
        DEFAULT_RETRY_SECONDS,
        5..3_600
      )
      [ base * (2**([ @upload.scan_attempts - 1, 0 ].max)), 1.hour.to_i ].min.seconds
    end

    def max_attempts
      configured_integer(
        "forum.attachments.scan_max_attempts",
        DEFAULT_MAX_ATTEMPTS,
        1..20
      )
    end

    def configured_hours(key, default)
      configured_integer(key, default, 1..(24 * 365))
    end

    def configured_integer(key, default, range)
      parsed = Integer(SiteSetting.get(key, default.to_s), exception: false)
      range.cover?(parsed) ? parsed : default
    end

    def instrument(name, extra = {})
      ActiveSupport::Notifications.instrument(
        name,
        {
          upload_id: @upload.id,
          attachment_id: @upload.forum_post_attachment_id,
          user_id: @upload.user_id,
          scan_attempts: @upload.scan_attempts,
          scanner: @upload.scanner
        }.merge(extra)
      )
    end
  end
end
