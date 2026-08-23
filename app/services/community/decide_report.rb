# frozen_string_literal: true

module Community
  class DecideReport < ApplicationService
    NOTIFICATION_TYPE = "forum.report_outcome"
    MAX_INTERNAL_NOTE_LENGTH = 5_000

    def initialize(report:, reviewer:, desired_status:, idempotency_key:, internal_note: nil,
                   expected_version: nil, require_expected_version: true, mutate_reportable: true)
      @report = report
      @reviewer = reviewer
      @desired_status = desired_status.to_s
      @idempotency_key = ReportMutationKey.normalize(idempotency_key)
      @internal_note = internal_note.to_s.strip.presence
      @expected_version = Integer(expected_version, exception: false)
      @require_expected_version = require_expected_version
      @mutate_reportable = mutate_reportable
    end

    def call
      return failure("report_state_invalid") unless Report::STAFF_FINAL_STATUSES.include?(@desired_status)
      return failure("report_reviewer_required") unless @reviewer&.persisted?
      return failure("report_idempotency_key_invalid") unless @idempotency_key
      return failure("report_internal_note_too_long") if @internal_note&.length.to_i > MAX_INTERNAL_NOTE_LENGTH
      if @require_expected_version && !(@expected_version && @expected_version >= 0)
        return failure("report_version_required")
      end

      result = nil
      Report.transaction(requires_new: true) do
        candidate = Report.find_by(id: @report&.id)
        unless candidate
          result = failure("report_not_found")
          raise ActiveRecord::Rollback
        end
        lock_hideable_target(candidate)
        report = Report.lock.find_by(id: candidate.id)
        unless report
          result = failure("report_not_found")
          raise ActiveRecord::Rollback
        end

        if report.status == @desired_status
          delivery = ensure_outcome_delivery!(report)
          subject_delivery = ensure_subject_action_delivery!(report)
          result = success(report:, delivery:, subject_delivery:, replayed: true)
          next
        end
        unless report.pending?
          result = failure("report_state_conflict")
          raise ActiveRecord::Rollback
        end
        if @expected_version && report.lock_version != @expected_version
          result = failure("report_version_conflict")
          raise ActiveRecord::Rollback
        end

        previous_version = report.lock_version
        affected_user = if @desired_status == "actioned"
          Community::ReportAffectedUserResolver.call(report.reportable)
        end
        report.update!(
          reviewer: @reviewer,
          review_note: @internal_note,
          reviewed_at: Time.current,
          status: @desired_status,
          affected_user: affected_user,
          dedupe_key: nil,
          state_changed_at: Time.current
        )
        mutation_result = mutate_reportable(report)
        if mutation_result.failure?
          result = failure("report_target_mutation_failed")
          raise ActiveRecord::Rollback
        end
        delivery = ensure_outcome_delivery!(report)
        subject_delivery = ensure_subject_action_delivery!(report)
        Administration::AuditLogger.call(
          actor: @reviewer,
          action: "community.report_decided",
          resource: report,
          request_id: @idempotency_key,
          reason: @internal_note,
          metadata: { public_outcome_code: report.public_outcome_code },
          before_state: { status: "pending", lock_version: previous_version },
          after_state: { status: report.status, lock_version: report.lock_version }
        )
        result = success(report:, delivery:, subject_delivery:, replayed: false)
      end
      result || failure("report_mutation_failed")
    rescue ActiveRecord::StaleObjectError
      failure("report_version_conflict")
    rescue ActiveRecord::Deadlocked,
      Community::SectionHierarchyLock::HierarchyChanged,
      Community::SectionHierarchyLock::TopicSectionChanged,
      Community::ReportTargetLock::PostTopicChanged
      failure("report_version_conflict")
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      failure("report_mutation_failed")
    end

    private

    def lock_hideable_target(report)
      reportable = report.reportable
      return unless Community::ReportTargetLock.hideable?(reportable)

      Community::ReportTargetLock.lock!(reportable)
    end

    def ensure_outcome_delivery!(report)
      existing = ReportOutcomeDelivery.find_by(forum_report_id: report.id)
      if existing
        unless existing.public_outcome_code == report.public_outcome_code
          raise ActiveRecord::RecordInvalid.new(existing)
        end
        return existing
      end

      notification = Community::InAppNotification.notify(
        user: report.reporter,
        notification_type: NOTIFICATION_TYPE,
        key: "report_outcome",
        metadata: {
          report_public_id: report.public_id,
          public_outcome_code: report.public_outcome_code,
          path: Rails.application.routes.url_helpers.forum_report_path(report)
        },
        outcome: -> {
          I18n.t("mcweb.forum.reports.public_outcomes.#{report.public_outcome_code}")
        }
      )
      ReportOutcomeDelivery.create!(
        report: report,
        notification: notification,
        public_outcome_code: report.public_outcome_code,
        idempotency_key_digest: ReportMutationKey.digest(@idempotency_key)
      )
    end

    def ensure_subject_action_delivery!(report)
      return unless report.actioned? && report.affected_user

      existing = ReportSubjectActionDelivery.find_by(forum_report_id: report.id)
      return existing if existing

      notification = Community::InAppNotification.notify(
        user: report.affected_user,
        notification_type: "forum.report_subject_action",
        key: "report_subject_action",
        metadata: {
          report_public_id: report.public_id,
          path: Rails.application.routes.url_helpers.forum_report_appeals_path
        }
      )
      ReportSubjectActionDelivery.create!(
        report:,
        notification:,
        created_at: Time.current
      )
    end

    def mutate_reportable(report)
      return ServiceResult.success(skipped: true) unless @mutate_reportable

      case @desired_status
      when "actioned"
        Community::HideReportable.call(reportable: report.reportable)
      when "dismissed"
        # A hidden target may have been hidden by a separate moderation action.
        # Without durable hide provenance, a report decision must fail closed
        # instead of republishing content implicitly.
        ServiceResult.success(skipped: "report_hide_requires_explicit_restore")
      else
        ServiceResult.success(skipped: true)
      end
    end

    def success(**value)
      ServiceResult.success(value)
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
