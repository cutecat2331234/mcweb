# frozen_string_literal: true

module Community
  class DecideReportAppeal < ApplicationService
    NOTIFICATION_TYPE = "forum.report_appeal_outcome"
    DECISIONS = %w[upheld overturned].freeze

    def initialize(appeal:, reviewer:, decision:, internal_note:, idempotency_key:,
                   expected_version:, now: Time.current)
      @appeal = appeal
      @reviewer = reviewer
      @decision = decision.to_s
      @internal_note = internal_note.to_s.strip.presence
      @idempotency_key = ReportMutationKey.normalize(idempotency_key)
      @expected_version = Integer(expected_version, exception: false)
      @now = now
    end

    def call
      validation = validation_failure
      return validation if validation

      digest = ReportMutationKey.digest(@idempotency_key)
      fingerprint = ReportAppealMutation.fingerprint(
        appeal_public_id: @appeal.public_id,
        reviewer_id: @reviewer.id,
        decision: @decision,
        internal_note: @internal_note
      )
      result = nil

      ReportAppeal.transaction(requires_new: true) do
        report = Report.lock.find_by(id: @appeal.forum_report_id)
        appeal = ReportAppeal.lock.find_by(id: @appeal.id)
        unless report && appeal && ReportAppealPolicy.new(@reviewer).reviewer_visible?(appeal)
          result = failure("report_appeal_unavailable")
          raise ActiveRecord::Rollback
        end
        lock_users(report, appeal)

        if appeal.status == @decision
          result = replay_result(appeal, digest, fingerprint)
          next
        end
        unless appeal.submitted? || appeal.under_review?
          result = failure("report_appeal_state_conflict")
          raise ActiveRecord::Rollback
        end
        if appeal.lock_version != @expected_version
          result = failure("report_appeal_version_conflict")
          raise ActiveRecord::Rollback
        end

        if appeal.submitted?
          previous_version = appeal.lock_version
          appeal.update!(
            status: "under_review",
            reviewer: @reviewer,
            review_started_at: @now,
            state_changed_at: @now
          )
          ReportAppealMutation.record_event!(
            appeal:,
            actor: @reviewer,
            event_type: "review_started",
            from_status: "submitted",
            to_status: "under_review",
            idempotency_key_digest: digest,
            request_fingerprint: fingerprint,
            occurred_at: @now
          )
          Administration::AuditLogger.call(
            actor: @reviewer,
            action: "community.report_appeal_review_started",
            resource: appeal,
            request_id: @idempotency_key,
            before_state: { status: "submitted", lock_version: previous_version },
            after_state: { status: "under_review", lock_version: appeal.lock_version }
          )
        elsif appeal.reviewer_id != @reviewer.id
          result = failure("report_appeal_reviewer_conflict")
          raise ActiveRecord::Rollback
        end

        previous_version = appeal.lock_version
        appeal.update!(
          status: @decision,
          public_outcome_code: @decision,
          internal_note: @internal_note,
          state_changed_at: @now,
          decided_at: @now,
          decision_idempotency_key_digest: digest,
          decision_request_fingerprint: fingerprint
        )
        ReportAppealMutation.record_event!(
          appeal:,
          actor: @reviewer,
          event_type: @decision,
          from_status: "under_review",
          to_status: @decision,
          public_outcome_code: @decision,
          idempotency_key_digest: digest,
          request_fingerprint: fingerprint,
          occurred_at: @now
        )
        delivery = ensure_outcome_delivery!(appeal)
        Administration::AuditLogger.call(
          actor: @reviewer,
          action: "community.report_appeal_decided",
          resource: appeal,
          request_id: @idempotency_key,
          reason: @internal_note,
          metadata: {
            public_outcome_code: @decision,
            appellant_role: appeal.appellant_role,
            moderation_reversal: "not_automatic"
          },
          before_state: { status: "under_review", lock_version: previous_version },
          after_state: { status: appeal.status, lock_version: appeal.lock_version }
        )
        result = success(appeal, delivery:, replayed: false)
      end

      publish_decision(result)
      result || failure("report_appeal_mutation_failed")
    rescue ActiveRecord::StaleObjectError
      failure("report_appeal_version_conflict")
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ActiveRecord::Deadlocked
      failure("report_appeal_mutation_failed")
    end

    private

    def validation_failure
      return failure("report_appeal_unavailable") unless @appeal&.persisted? && @reviewer&.persisted?
      return failure("report_appeal_decision_invalid") unless DECISIONS.include?(@decision)
      return failure("report_appeal_internal_note_too_long") if @internal_note&.length.to_i > ReportAppeal::MAX_INTERNAL_NOTE_LENGTH
      return failure("report_appeal_idempotency_key_invalid") unless @idempotency_key
      return failure("report_appeal_version_required") unless @expected_version&.nonnegative?

      nil
    end

    def lock_users(report, appeal)
      User.where(id: [ report.reporter_id, report.affected_user_id, appeal.appellant_id, @reviewer.id ].compact.uniq)
        .order(:id)
        .lock
        .load
    end

    def ensure_outcome_delivery!(appeal)
      existing = ReportAppealOutcomeDelivery.find_by(forum_report_appeal_id: appeal.id)
      if existing
        raise ActiveRecord::RecordInvalid.new(existing) unless existing.public_outcome_code == appeal.public_outcome_code

        return existing
      end

      notification = Community::InAppNotification.notify(
        user: appeal.appellant,
        notification_type: NOTIFICATION_TYPE,
        key: "report_appeal_outcome",
        metadata: {
          appeal_public_id: appeal.public_id,
          public_outcome_code: appeal.public_outcome_code,
          path: Rails.application.routes.url_helpers.forum_report_appeal_path(appeal)
        },
        outcome: -> {
          I18n.t("mcweb.forum.report_appeals.public_outcomes.#{appeal.public_outcome_code}")
        }
      )
      ReportAppealOutcomeDelivery.create!(
        appeal:,
        notification:,
        public_outcome_code: appeal.public_outcome_code,
        created_at: @now
      )
    end

    def replay_result(appeal, digest, fingerprint)
      matches = ReportAppealMutation.secure_match?(appeal.decision_idempotency_key_digest, digest) &&
        ReportAppealMutation.secure_match?(appeal.decision_request_fingerprint, fingerprint)
      return failure("report_appeal_idempotency_conflict") unless matches

      delivery = ReportAppealOutcomeDelivery.find_by(forum_report_appeal_id: appeal.id)
      success(appeal, delivery:, replayed: true)
    end

    def publish_decision(result)
      return unless result&.success? && !result.value.fetch(:replayed)

      Mcweb::Events.publish(
        "forum.report_appeal.decided",
        appeal: result.value.fetch(:appeal),
        reviewer: @reviewer
      )
    end

    def success(appeal, delivery:, replayed:)
      ServiceResult.success(appeal:, delivery:, replayed:)
    end

    def failure(code)
      ReportAppealMutation.failure(code)
    end
  end
end
