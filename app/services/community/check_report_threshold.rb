# frozen_string_literal: true

module Community
  class CheckReportThreshold < ApplicationService
    def initialize(report:)
      @report = report
    end

    def call
      threshold = SiteSetting.get("forum.report_auto_hide_threshold", "5").to_i
      return ServiceResult.success(skipped: true) if threshold <= 0

      reportable = @report.reportable
      return ServiceResult.success(skipped: true) unless reportable

      reporter_ids = Community::Report
        .where(reportable: reportable, status: :pending)
        .distinct
        .pluck(:reporter_id)
        .reject { |reporter_id| flag_abuser?(reporter_id) }

      pending_count = reporter_ids.size
      return ServiceResult.success(skipped: true) if pending_count < threshold

      case reportable
      when Community::Post
        reportable.update!(status: :hidden) unless reportable.deleted_at.present?
        Community::SyncTopicLastPost.call(topic: reportable.topic)
      when Community::Topic
        reportable.update!(status: :hidden)
      when Community::ProfilePost
        reportable.update!(status: :hidden) unless reportable.deleted_at.present?
      end

      ServiceResult.success(hidden: true, pending_count: pending_count)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    # A reporter whose flags are repeatedly dismissed loses auto-hide weight, so a
    # brigade of false-flaggers cannot hide content. Off by default (threshold 0).
    def flag_abuser?(reporter_id)
      threshold = SiteSetting.get("forum.flag_abuse_threshold", "0").to_i
      return false if threshold <= 0

      Community::Report.where(reporter_id: reporter_id, status: :dismissed).count >= threshold
    end
  end
end
