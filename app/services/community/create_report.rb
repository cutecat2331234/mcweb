# frozen_string_literal: true

module Community
  class CreateReport < ApplicationService
    REPORTABLE_TYPES = %w[
      Community::Topic
      Community::Post
      Community::Message
      Community::ProfilePost
      Community::ProfilePostComment
      Commerce::Review
      User
    ].freeze
    MAX_DETAIL_LENGTH = Community::Report::MAX_REASON_LENGTH

    def initialize(reporter:, reportable_type:, reportable_id:, reason_code: nil,
                   reason_detail: nil, reason: nil, ip_address: nil)
      @reporter = reporter
      @reportable_type = reportable_type.to_s
      @reportable_id = reportable_id
      @reason_code = reason_code.to_s.strip.presence
      @reason_detail = reason_detail.to_s.strip
      @legacy_reason = reason.to_s.strip
      @ip_address = ip_address
    end

    def call
      return failure("report_target_unavailable") unless @reporter&.persisted?

      reportable = find_reportable
      return failure("report_target_unavailable") unless reportable
      return failure("report_reason_invalid") unless reason_valid?
      return failure("report_detail_too_long") if report_text_too_long?

      rate_limit = Administration::AbuseRateLimit.call(
        action: :report,
        account: @reporter,
        ip_address: @ip_address
      )
      return rate_limit if rate_limit.failure?

      report = nil
      evidence_result = nil
      Community::Report.transaction do
        reportable.lock!
        unless accessible?(reportable, lock_membership: true)
          evidence_result = failure("report_target_unavailable")
          raise ActiveRecord::Rollback
        end

        evidence_result = Community::BuildReportEvidence.call(reportable: reportable)
        raise ActiveRecord::Rollback if evidence_result.failure?

        report = Community::Report.create!(
          reporter: @reporter,
          reportable: reportable,
          reason: reason_text,
          reason_code: @reason_code,
          dedupe_key: dedupe_key(reportable),
          status: :pending
        )
        evidence = report.create_evidence!(**evidence_result.value)
        audit_result = Administration::AuditLogger.call(
          actor: @reporter,
          action: "community.report_created",
          resource: report,
          metadata: {
            reportable_type: reportable.class.name,
            reportable_id: reportable.id,
            subject_revision: evidence.subject_revision,
            content_digest: evidence.content_digest
          }
        )
        if audit_result.failure?
          report = nil
          raise ActiveRecord::Rollback
        end
      end
      return evidence_result if evidence_result&.failure?
      return failure("report_create_failed") unless report&.persisted?

      Community::CheckReportThreshold.call(report: report)
      Mcweb::Events.publish(
        "forum.report.created",
        report: report,
        reporter: @reporter,
        reportable: reportable
      )
      ServiceResult.success(report)
    rescue ActiveRecord::RecordNotFound
      failure("report_target_unavailable")
    rescue ActiveRecord::RecordNotUnique
      failure("report_already_submitted")
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end

    def find_reportable
      return unless REPORTABLE_TYPES.include?(@reportable_type)

      record = @reportable_type.constantize.find_by(id: @reportable_id)
      record if record && accessible?(record)
    end

    def accessible?(record, lock_membership: false)
      case record
      when Community::Topic
        PollParticipation.visible?(topic: record, user: @reporter)
      when Community::Post
        PostAccess.readable?(post: record, user: @reporter)
      when Community::Message
        participant = if lock_membership
          record.conversation.participants.where(user: @reporter).lock.first.present?
        else
          record.conversation.participant?(@reporter)
        end
        !record.deleted? && record.user_id != @reporter.id && participant
      when Community::ProfilePost
        record.published? && record.deleted_at.nil?
      when Community::ProfilePostComment
        record.published? && record.deleted_at.nil? && record.profile_post&.published? == true
      when Commerce::Review
        record.published?
      when User
        record.id != @reporter.id && record.active?
      else
        false
      end
    end

    def reason_valid?
      return Community::Report.reason_options.key?(@reason_code) if @reason_code

      @legacy_reason.present?
    end

    def reason_text
      return @legacy_reason unless @reason_code

      @reason_detail.presence || @reason_code
    end

    def report_text_too_long?
      @reason_detail.length > MAX_DETAIL_LENGTH || @legacy_reason.length > MAX_DETAIL_LENGTH
    end

    def dedupe_key(reportable)
      Digest::SHA256.hexdigest([ @reporter.id, reportable.class.name, reportable.id ].join(":"))
    end
  end
end
