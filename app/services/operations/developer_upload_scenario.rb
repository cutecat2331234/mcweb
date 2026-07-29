# frozen_string_literal: true

module Operations
  class DeveloperUploadScenario < ApplicationService
    SCENARIOS = %w[clean infected quarantined timeout].freeze

    def initialize(upload:, scenario:, actor:, now: Time.current)
      @upload = upload
      @scenario = scenario.to_s
      @actor = actor
      @now = now
    end

    def call
      return unavailable unless Mcweb::DeveloperMode.enabled?
      return invalid_scenario unless SCENARIOS.include?(@scenario)
      return invalid_upload unless @upload&.kind_post_attachment?
      return invalid_upload unless @upload.status_stored? ||
        @upload.status_linked?

      @upload.with_lock do
        before_state = snapshot(@upload)
        @upload.update!(scenario_attributes)
        Administration::AuditLogger.call(
          actor: @actor,
          action: "developer_mode.attachment_scenario_applied",
          resource: @upload,
          metadata: { scenario: @scenario },
          before_state: before_state,
          after_state: snapshot(@upload)
        )
      end

      ServiceResult.success(@upload)
    end

    private

    def scenario_attributes
      shared = {
        scanner: "developer_mode_scenario",
        scan_attempts: @upload.scan_attempts.to_i + 1,
        scan_started_at: nil,
        manual_review_status: "none",
        manual_reviewed_at: nil,
        manual_reviewed_by_id: nil,
        manual_review_revoked_at: nil,
        manual_review_revoked_by_id: nil,
        manual_review_source_result_code: nil,
        manual_review_file_sha256: nil
      }

      case @scenario
      when "clean"
        shared.merge(
          scan_status: "clean",
          scan_result_code: "developer_fixture_clean",
          scan_error_message: nil,
          scanned_at: @now,
          quarantined_at: nil,
          next_scan_at: nil
        )
      when "infected"
        shared.merge(
          scan_status: "infected",
          scan_result_code: "developer_fixture_infected",
          scan_error_message: nil,
          scanned_at: @now,
          quarantined_at: @now,
          next_scan_at: nil
        )
      when "quarantined"
        shared.merge(
          scan_status: "error",
          scan_result_code: "developer_fixture_quarantined",
          scan_error_message: "Developer Mode quarantine scenario",
          scanned_at: @now,
          quarantined_at: @now,
          next_scan_at: nil
        )
      when "timeout"
        shared.merge(
          scan_status: "error",
          scan_result_code: "developer_fixture_timeout",
          scan_error_message: "Developer Mode scanner timeout",
          scanned_at: @now,
          quarantined_at: nil,
          next_scan_at: 5.minutes.since(@now)
        )
      end
    end

    def snapshot(upload)
      {
        scan_status: upload.scan_status,
        scanner: upload.scanner,
        scan_result_code: upload.scan_result_code,
        quarantined_at: upload.quarantined_at&.iso8601,
        next_scan_at: upload.next_scan_at&.iso8601
      }
    end

    def unavailable
      ServiceResult.failure(
        error: "developer_mode_not_enabled",
        code: "developer_mode_not_enabled"
      )
    end

    def invalid_scenario
      ServiceResult.failure(
        error: "developer_attachment_scenario_invalid",
        code: "developer_attachment_scenario_invalid"
      )
    end

    def invalid_upload
      ServiceResult.failure(
        error: "developer_attachment_unavailable",
        code: "developer_attachment_unavailable"
      )
    end
  end
end
