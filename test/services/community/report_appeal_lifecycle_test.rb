# frozen_string_literal: true

require "test_helper"
require "tempfile"

module Community
  class ReportAppealLifecycleTest < ActiveSupport::TestCase
    include Rails.application.routes.url_helpers

    setup do
      @reporter = create_user
      @affected_user = create_user
      @reviewer = create_user
      grant_permission(@reviewer, "forum.topics.lock")
      @temporary_files = []
    end

    teardown do
      @temporary_files.each(&:close!)
    end

    test "reporter reconsideration is role isolated idempotent and terminal" do
      report = create_decided_report(status: "dismissed")
      draft_key = SecureRandom.uuid
      drafted = create_draft(report:, appellant: @reporter, role: "reporter", key: draft_key)
      assert_predicate drafted, :success?, drafted.error
      appeal = drafted.value.fetch(:appeal)
      assert_predicate appeal, :draft?
      assert Community::ReportAppealPolicy.new(@reporter).appellant_visible?(appeal)
      assert_not Community::ReportAppealPolicy.new(@affected_user).appellant_visible?(appeal)
      assert_not Community::ReportAppealPolicy.new(@reviewer).review_scope.exists?(appeal.id)

      replay = create_draft(report:, appellant: @reporter, role: "reporter", key: draft_key)
      assert_predicate replay, :success?, replay.error
      assert_equal appeal.id, replay.value.fetch(:appeal).id

      submit_key = SecureRandom.uuid
      submitted = submit_appeal(appeal:, key: submit_key, reason: "The decision missed relevant context")
      assert_predicate submitted, :success?, submitted.error
      assert_predicate appeal.reload, :submitted?
      grant_permission(@reporter, "forum.topics.lock")
      assert_not Community::ReportAppealPolicy.new(@reporter).reviewer_visible?(appeal)

      submit_replay = submit_appeal(
        appeal:,
        key: submit_key,
        reason: "The decision missed relevant context",
        version: 0
      )
      assert_predicate submit_replay, :success?, submit_replay.error
      assert_equal true, submit_replay.value.fetch(:replayed)

      changed_replay = submit_appeal(
        appeal:,
        key: submit_key,
        reason: "Different payload",
        version: appeal.lock_version
      )
      assert_equal "report_appeal_idempotency_conflict", changed_replay.code

      original_submit_fingerprint = appeal.submit_request_fingerprint
      assert_not appeal.update(submit_request_fingerprint: "0" * 64)
      assert_predicate appeal.errors[:base], :present?
      assert_equal original_submit_fingerprint, appeal.reload.submit_request_fingerprint

      decision_key = SecureRandom.uuid
      assert_difference -> { Notification.where(notification_type: "forum.report_appeal_outcome").count }, 1 do
        decided = Community::DecideReportAppeal.call(
          appeal:,
          reviewer: @reviewer,
          decision: "upheld",
          internal_note: "private reviewer note",
          idempotency_key: decision_key,
          expected_version: appeal.lock_version
        )
        assert_predicate decided, :success?, decided.error
      end

      assert_predicate appeal.reload, :upheld?
      assert_equal %w[drafted submitted review_started upheld], appeal.events.timeline.pluck(:event_type)
      public_payload = Community::ReportAppealSerializer.new(appeal:, viewer: @reporter).detail
      assert_not_includes public_payload.to_json, "private reviewer note"

      decision_replay = Community::DecideReportAppeal.call(
        appeal:,
        reviewer: @reviewer,
        decision: "upheld",
        internal_note: "private reviewer note",
        idempotency_key: decision_key,
        expected_version: 0
      )
      assert_predicate decision_replay, :success?, decision_replay.error
      assert_equal true, decision_replay.value.fetch(:replayed)
      assert_equal 1, appeal.events.where(event_type: "upheld").count
    end

    test "affected subject receives a safe appeal right without reporter context" do
      report = create_decided_report(status: "actioned")
      assert_equal @affected_user.id, report.reload.affected_user_id
      delivery = report.subject_action_delivery
      assert_equal @affected_user.id, delivery.notification.user_id
      assert_equal forum_report_appeals_path, delivery.notification.destination_path

      wrong_role = create_draft(
        report:,
        appellant: @reporter,
        role: "affected_subject",
        key: SecureRandom.uuid
      )
      assert_equal "report_appeal_unavailable", wrong_role.code

      drafted = create_draft(
        report:,
        appellant: @affected_user,
        role: "affected_subject",
        key: SecureRandom.uuid
      )
      assert_predicate drafted, :success?, drafted.error
      appeal = drafted.value.fetch(:appeal)
      safe_report = Community::ReportAppealSerializer.new(appeal:, viewer: @affected_user)
        .detail.fetch(:report)
      assert_equal %i[public_id target_label], safe_report.keys
      refute_includes safe_report.to_json, @reporter.username
      refute_includes safe_report.to_json, report.reason
      grant_permission(@reporter, "forum.topics.lock")
      assert_not Community::ReportAppealPolicy.new(@reporter).reviewer_visible?(appeal)
      assert_not Community::ReportAppealPolicy.new(@reporter).visible_scope.exists?(appeal.id)
      grant_permission(@affected_user, "forum.topics.lock")
      assert_not Community::ReportAppealPolicy.new(@affected_user).report_visible_to_reviewer?(report)

      cancel_key = SecureRandom.uuid
      cancelled = Community::CancelReportAppeal.call(
        appeal:,
        appellant: @affected_user,
        idempotency_key: cancel_key,
        expected_version: appeal.lock_version
      )
      assert_predicate cancelled, :success?, cancelled.error
      assert_predicate appeal.reload, :cancelled?

      replay = Community::CancelReportAppeal.call(
        appeal:,
        appellant: @affected_user,
        idempotency_key: cancel_key,
        expected_version: 0
      )
      assert_predicate replay, :success?, replay.error
      assert_equal true, replay.value.fetch(:replayed)

      delayed_submit = submit_appeal(appeal:, key: SecureRandom.uuid, reason: "Too late")
      assert_equal "report_appeal_state_conflict", delayed_submit.code
    end

    test "an actioned report without a safely resolved subject does not invent an appeal right" do
      created = Community::CreateReport.call(
        reporter: @reporter,
        reportable_type: "User",
        reportable_id: @affected_user.id,
        reason_code: "offensive",
        reason_detail: "Reporter-private details",
        ip_address: "127.0.0.1"
      )
      assert_predicate created, :success?, created.error
      report = created.value

      decided = Community::ReportAffectedUserResolver.stub(:call, nil) do
        Community::DecideReport.call(
          report:,
          reviewer: @reviewer,
          desired_status: "actioned",
          idempotency_key: SecureRandom.uuid,
          expected_version: report.lock_version
        )
      end

      assert_predicate decided, :success?, decided.error
      assert_predicate report.reload, :actioned?
      assert_nil report.affected_user_id
      assert_nil report.subject_action_delivery
      assert_empty Community::ReportAppealPolicy.new(@affected_user).eligible_roles(report)
    end

    test "section moderators see only appeals for reports in their assigned sections" do
      suffix = SecureRandom.hex(4)
      category = Community::Category.create!(name: "Appeals #{suffix}", slug: "appeals-#{suffix}")
      section = Community::Section.create!(
        category:,
        name: "Appeal section",
        slug: "appeal-section-#{suffix}",
        position: 0
      )
      topic = Community::Topic.create!(
        public_id: "topic_#{SecureRandom.alphanumeric(16)}",
        section:,
        user: @affected_user,
        title: "Appeal policy topic",
        status: "published",
        last_posted_at: Time.current,
        last_post_user: @affected_user,
        replies_count: 0
      )
      post = Community::Post.create!(
        topic:,
        user: @affected_user,
        floor_number: 1,
        body: "Appeal policy post",
        status: "published"
      )
      created = Community::CreateReport.call(
        reporter: @reporter,
        reportable_type: "Community::Post",
        reportable_id: post.id,
        reason_code: "offensive",
        reason_detail: "Section-scoped report",
        ip_address: "127.0.0.1"
      )
      assert_predicate created, :success?, created.error
      report = created.value
      decision = Community::DecideReport.call(
        report:,
        reviewer: @reviewer,
        desired_status: "dismissed",
        idempotency_key: SecureRandom.uuid,
        expected_version: report.lock_version
      )
      assert_predicate decision, :success?, decision.error
      appeal = create_draft(
        report: report.reload,
        appellant: @reporter,
        role: "reporter",
        key: SecureRandom.uuid
      ).value.fetch(:appeal)
      submitted = submit_appeal(appeal:, key: SecureRandom.uuid, reason: "Review this section case")
      assert_predicate submitted, :success?, submitted.error

      section_moderator = create_user
      unrelated_user = create_user
      Community::SectionModerator.create!(section:, user: section_moderator)
      assert Community::ReportAppealPolicy.new(section_moderator).reviewer_visible?(appeal.reload)
      assert Community::ReportAppealPolicy.new(section_moderator).visible_scope.exists?(appeal.id)
      assert_not Community::ReportAppealPolicy.new(unrelated_user).reviewer_visible?(appeal)
    end

    test "submission seals only clean same-subject evidence atomically" do
      report = create_decided_report(status: "dismissed")
      appeal = create_draft(
        report:,
        appellant: @reporter,
        role: "reporter",
        key: SecureRandom.uuid
      ).value.fetch(:appeal)
      attachment = create_evidence(appeal:)
      omitted_attachment = create_evidence(appeal:)
      key = SecureRandom.uuid

      pending = submit_appeal(
        appeal:,
        key:,
        reason: "Evidence supports reconsideration",
        attachment_ids: [ attachment.public_id ]
      )
      assert_equal "report_evidence_not_clean", pending.code
      assert_predicate appeal.reload, :draft?
      assert_empty appeal.evidence_links

      mark_evidence_clean!(attachment)
      submitted = submit_appeal(
        appeal:,
        key:,
        reason: "Evidence supports reconsideration",
        attachment_ids: [ attachment.public_id ]
      )
      assert_predicate submitted, :success?, submitted.error
      assert_predicate appeal.reload, :submitted?
      assert_equal [ attachment.id ], appeal.evidence_links.pluck(:secure_evidence_attachment_id)
      assert_equal [ "appellant" ], appeal.evidence_links.pluck(:audience)
      assert_not SecureEvidence::AttachmentAccess.discard_allowed?(attachment, actor: @reporter)
      assert SecureEvidence::AttachmentAccess.discard_allowed?(omitted_attachment, actor: @reporter)
      payload = Community::ReportAppealSerializer.new(appeal:, viewer: @reporter).detail
      omitted_payload = payload.fetch(:attachments).find do |item|
        item.fetch(:public_id) == omitted_attachment.public_id
      end
      assert_equal false, omitted_payload.fetch(:sealed)
      assert_predicate omitted_payload.fetch(:discard_url), :present?
    end

    private

    def create_decided_report(status:)
      created = Community::CreateReport.call(
        reporter: @reporter,
        reportable_type: "User",
        reportable_id: @affected_user.id,
        reason_code: "offensive",
        reason_detail: "Reporter-private details",
        ip_address: "127.0.0.1"
      )
      assert_predicate created, :success?, created.error
      report = created.value
      decided = Community::DecideReport.call(
        report:,
        reviewer: @reviewer,
        desired_status: status,
        idempotency_key: SecureRandom.uuid,
        expected_version: report.lock_version
      )
      assert_predicate decided, :success?, decided.error
      report.reload
    end

    def create_draft(report:, appellant:, role:, key:)
      Community::CreateReportAppealDraft.call(
        report:,
        appellant:,
        appellant_role: role,
        idempotency_key: key
      )
    end

    def submit_appeal(appeal:, key:, reason:, version: appeal.lock_version, attachment_ids: [])
      Community::SubmitReportAppeal.call(
        appeal:,
        appellant: appeal.appellant,
        reason:,
        attachment_public_ids: attachment_ids,
        idempotency_key: key,
        expected_version: version
      )
    end

    def create_evidence(appeal:)
      tempfile = Tempfile.new([ "report-evidence", ".txt" ])
      tempfile.binmode
      tempfile.write("appeal evidence")
      tempfile.rewind
      @temporary_files << tempfile
      file = ActionDispatch::Http::UploadedFile.new(
        tempfile:,
        filename: "appeal-evidence.txt",
        type: "text/plain"
      )
      result = SecureEvidence::CreateAttachment.call(
        actor: @reporter,
        subject_key: "community.report_appeal",
        subject_public_id: appeal.public_id,
        file:,
        idempotency_key: SecureRandom.uuid
      )
      assert_predicate result, :success?, result.error
      result.value.fetch(:attachment)
    end

    def mark_evidence_clean!(attachment)
      now = Time.current
      attachment.upload_record.update!(
        status: "linked",
        expires_at: nil,
        scan_status: "clean",
        scanner: "test_scanner",
        scan_result_code: "clean",
        scanned_at: now,
        next_scan_at: nil
      )
      attachment.update!(state: "available", scanned_at: now)
    end
  end
end
