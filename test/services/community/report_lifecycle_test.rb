# frozen_string_literal: true

require "test_helper"

module Community
  class ReportLifecycleTest < ActiveSupport::TestCase
    include Rails.application.routes.url_helpers

    setup do
      @reporter = create_user
      @reviewer = create_user
      @target = create_user
    end

    test "supplements are owner scoped versioned immutable and idempotent" do
      report = create_report
      version = report.lock_version
      key = SecureRandom.uuid

      first = Community::AddReportSupplement.call(
        report:,
        reporter: @reporter,
        body: "Additional context",
        idempotency_key: key,
        expected_version: version
      )
      assert_predicate first, :success?, first.error
      assert_equal false, first.value.fetch(:replayed)
      assert_operator report.reload.lock_version, :>, version

      replay = Community::AddReportSupplement.call(
        report:,
        reporter: @reporter,
        body: "Additional context",
        idempotency_key: key,
        expected_version: version
      )
      assert_predicate replay, :success?, replay.error
      assert_equal true, replay.value.fetch(:replayed)
      assert_equal 1, report.supplements.count

      reused = Community::AddReportSupplement.call(
        report:,
        reporter: @reporter,
        body: "Different context",
        idempotency_key: key,
        expected_version: report.lock_version
      )
      assert_predicate reused, :failure?
      assert_equal "report_idempotency_key_reused", reused.code

      stale = Community::AddReportSupplement.call(
        report:,
        reporter: @reporter,
        body: "New context",
        idempotency_key: SecureRandom.uuid,
        expected_version: version
      )
      assert_predicate stale, :failure?
      assert_equal "report_version_conflict", stale.code

      supplement = report.supplements.first
      supplement.body = "changed"
      assert_not supplement.save
      assert_equal "Additional context", supplement.reload.body
      assert_raises ActiveRecord::StatementInvalid do
        Community::ReportSupplement.transaction(requires_new: true) do
          Community::ReportSupplement.where(id: supplement.id).update_all(body: "database bypass")
        end
      end
      assert_equal "Additional context", supplement.reload.body
      assert_not supplement.destroy
    end

    test "withdrawal converges on the desired state and preserves evidence" do
      report = create_report
      evidence_id = report.evidence.id
      key = SecureRandom.uuid

      first = Community::WithdrawReport.call(
        report:,
        reporter: @reporter,
        desired_state: "withdrawn",
        idempotency_key: key,
        expected_version: report.lock_version
      )
      assert_predicate first, :success?, first.error
      assert_equal false, first.value.fetch(:replayed)
      assert_predicate report.reload, :withdrawn?
      assert_nil report.dedupe_key
      assert_equal "withdrawn", report.public_outcome_code
      assert_equal evidence_id, report.evidence.id

      replay = Community::WithdrawReport.call(
        report:,
        reporter: @reporter,
        desired_state: "withdrawn",
        idempotency_key: SecureRandom.uuid,
        expected_version: 0
      )
      assert_predicate replay, :success?, replay.error
      assert_equal true, replay.value.fetch(:replayed)

      supplement = Community::AddReportSupplement.call(
        report:,
        reporter: @reporter,
        body: "Too late",
        idempotency_key: SecureRandom.uuid,
        expected_version: report.lock_version
      )
      assert_predicate supplement, :failure?
      assert_equal "report_not_pending", supplement.code
    end

    test "report mutations fail closed for a different reporter" do
      report = create_report
      stranger = create_user

      supplement = Community::AddReportSupplement.call(
        report:,
        reporter: stranger,
        body: "Not mine",
        idempotency_key: SecureRandom.uuid,
        expected_version: report.lock_version
      )
      withdrawal = Community::WithdrawReport.call(
        report:,
        reporter: stranger,
        desired_state: "withdrawn",
        idempotency_key: SecureRandom.uuid,
        expected_version: report.lock_version
      )

      assert_equal "report_not_found", supplement.code
      assert_equal "report_not_found", withdrawal.code
      assert_predicate report.reload, :pending?
    end

    test "withdrawal and dismissal never reopen content hidden by another moderation path" do
      author = create_user
      _topic, post = create_visible_forum_notification_resource(user: author, title: "Hide provenance")
      first = create_report_for(reporter: @reporter, reportable: post, detail: "First detail")
      second_reporter = create_user
      second = create_report_for(reporter: second_reporter, reportable: post, detail: "Second detail")
      post.update!(status: "hidden")

      withdrawn = Community::WithdrawReport.call(
        report: first,
        reporter: @reporter,
        desired_state: "withdrawn",
        idempotency_key: SecureRandom.uuid,
        expected_version: first.lock_version
      )
      assert_predicate withdrawn, :success?, withdrawn.error
      assert_equal "hidden", post.reload.status

      dismissed = Community::DecideReport.call(
        report: second,
        reviewer: @reviewer,
        desired_status: "dismissed",
        idempotency_key: SecureRandom.uuid,
        expected_version: second.lock_version
      )
      assert_predicate dismissed, :success?, dismissed.error
      assert_equal "hidden", post.reload.status
    end

    test "a staff decision atomically creates one persistent safe outcome notification" do
      report = create_report
      key = SecureRandom.uuid

      assert_difference -> { Notification.where(notification_type: "forum.report_outcome").count }, 1 do
        assert_difference -> { Community::ReportOutcomeDelivery.count }, 1 do
          assert_difference -> { Operations::DurableEnqueueIntent.count }, 1 do
            result = decide(report:, key:)
            assert_predicate result, :success?, result.error
            assert_equal false, result.value.fetch(:replayed)
          end
        end
      end

      report.reload
      assert_predicate report, :actioned?
      assert_equal "action_taken", report.public_outcome_code
      delivery = report.outcome_delivery
      notification = delivery.notification
      assert_equal @reporter.id, notification.user_id
      assert_equal false, notification.auto_dismiss
      metadata = notification.reload.metadata.stringify_keys
      assert_equal %w[path public_outcome_code report_id], metadata.keys.sort
      assert_equal forum_report_path(report), metadata.fetch("path")
      refute_includes metadata.to_json, @reviewer.username
      refute_includes metadata.to_json, "internal decision"

      assert_no_difference -> { Notification.where(notification_type: "forum.report_outcome").count } do
        assert_no_difference -> { Community::ReportOutcomeDelivery.count } do
          replay = decide(report:, key: SecureRandom.uuid, expected_version: 0)
          assert_predicate replay, :success?, replay.error
          assert_equal true, replay.value.fetch(:replayed)
        end
      end

      notification.destroy!
      assert_nil delivery.reload.notification_id
      assert_no_difference -> { Notification.where(notification_type: "forum.report_outcome").count } do
        assert_predicate decide(report:, key: SecureRandom.uuid, expected_version: 0), :success?
      end
    end

    test "decision rollback does not leave a notification or durable enqueue intent" do
      report = create_report
      invalid_delivery = Community::ReportOutcomeDelivery.new
      create_failure = lambda do |*args, **kwargs|
        raise ActiveRecord::RecordInvalid.new(invalid_delivery)
      end

      assert_no_difference -> { Notification.where(notification_type: "forum.report_outcome").count } do
        assert_no_difference -> { Operations::DurableEnqueueIntent.count } do
          Community::ReportOutcomeDelivery.stub(:create!, create_failure) do
            result = decide(report:, key: SecureRandom.uuid)
            assert_predicate result, :failure?
            assert_equal "report_mutation_failed", result.code
          end
        end
      end
      assert_predicate report.reload, :pending?
      assert_nil report.public_outcome_code
    end

    test "an outcome receipt cannot be inserted as an undelivered tombstone" do
      report = create_report
      report.update!(
        reviewer: @reviewer,
        reviewed_at: Time.current,
        status: "dismissed",
        dedupe_key: nil
      )
      digest = Community::ReportMutationKey.digest(SecureRandom.uuid)
      delivery = Community::ReportOutcomeDelivery.new(
        report:,
        notification: nil,
        public_outcome_code: report.public_outcome_code,
        idempotency_key_digest: digest
      )
      assert_not delivery.valid?
      assert delivery.errors.of_kind?(:notification, :blank)

      assert_raises ActiveRecord::StatementInvalid do
        Community::ReportOutcomeDelivery.transaction(requires_new: true) do
          Community::ReportOutcomeDelivery.insert_all!([ {
            forum_report_id: report.id,
            notification_id: nil,
            public_outcome_code: report.public_outcome_code,
            idempotency_key_digest: digest,
            created_at: Time.current
          } ])
        end
      end
      assert_not Community::ReportOutcomeDelivery.exists?(forum_report_id: report.id)
    end

    test "database outcome shape rejects a terminal report without a public outcome" do
      report = create_report

      assert_raises ActiveRecord::StatementInvalid do
        Community::Report.transaction(requires_new: true) do
          Community::Report.where(id: report.id).update_all(
            status: "reviewed",
            public_outcome_code: nil,
            reviewed_at: Time.current,
            state_changed_at: Time.current
          )
        end
      end
      assert_predicate report.reload, :pending?
    end

    test "database transition guard prevents reopening or rewriting a terminal report" do
      report = create_report
      result = decide(report:, key: SecureRandom.uuid)
      assert_predicate result, :success?, result.error
      assert_predicate report.reload, :reviewed?

      assert_raises ActiveRecord::StatementInvalid do
        Community::Report.transaction(requires_new: true) do
          Community::Report.where(id: report.id).update_all(
            status: "pending",
            public_outcome_code: nil,
            state_changed_at: Time.current
          )
        end
      end
      assert_predicate report.reload, :reviewed?

      assert_raises ActiveRecord::StatementInvalid do
        Community::Report.transaction(requires_new: true) do
          Community::Report.where(id: report.id).update_all(
            status: "dismissed",
            public_outcome_code: "not_upheld",
            state_changed_at: Time.current
          )
        end
      end
      assert_predicate report.reload, :reviewed?
    end

    test "bulk decisions create one outcome per report without cross reporter metadata" do
      second_reporter = create_user
      second = Community::CreateReport.call(
        reporter: second_reporter,
        reportable_type: "User",
        reportable_id: @target.id,
        reason_code: "spam",
        reason_detail: "Second reporter detail",
        ip_address: "127.0.0.2"
      )
      assert_predicate second, :success?, second.error
      first = create_report
      request_key = SecureRandom.uuid
      first_result = nil

      assert_difference -> { Notification.where(notification_type: "forum.report_outcome").count }, 2 do
        assert_difference -> { Community::ReportOutcomeDelivery.count }, 2 do
          assert_difference -> { Community::ReportDecisionBatch.count }, 1 do
            first_result = Community::DecideReports.call(
              scope: Community::Report.all,
              reportable: @target,
              reviewer: @reviewer,
              desired_status: "dismissed",
              internal_note: "internal bulk note",
              idempotency_key: request_key
            )
          end
          assert_predicate first_result, :success?, first_result.error
          assert_equal 2, first_result.value.fetch(:count)
        end
      end

      late_reporter = create_user
      late = Community::CreateReport.call(
        reporter: late_reporter,
        reportable_type: "User",
        reportable_id: @target.id,
        reason_code: "other",
        reason_detail: "Arrived after the frozen batch",
        ip_address: "127.0.0.3"
      )
      assert_predicate late, :success?, late.error
      assert_no_difference -> { Notification.where(notification_type: "forum.report_outcome").count } do
        assert_no_difference -> { Community::ReportOutcomeDelivery.count } do
          replay = Community::DecideReports.call(
            scope: Community::Report.all,
            reportable: @target,
            reviewer: @reviewer,
            desired_status: "dismissed",
            internal_note: "internal bulk note",
            idempotency_key: request_key
          )
          assert_predicate replay, :success?, replay.error
          assert_equal true, replay.value.fetch(:replayed)
          assert_equal 2, replay.value.fetch(:count)
        end
      end
      assert_predicate late.value.reload, :pending?

      notifications = Notification.where(
        notification_type: "forum.report_outcome",
        user_id: [ @reporter.id, second_reporter.id ]
      )
      assert_equal 2, notifications.count
      notifications.each do |notification|
        metadata = notification.metadata.stringify_keys
        assert_equal %w[path public_outcome_code report_id], metadata.keys.sort
        refute_includes metadata.to_json, "2 reports"
        refute_includes metadata.to_json, "internal bulk note"
      end
      assert_predicate first.reload, :dismissed?
      assert_predicate second.value.reload, :dismissed?
    end

    test "notification access requires the durable receipt owner outcome and private path" do
      report = create_report
      result = decide(report:, key: SecureRandom.uuid)
      assert_predicate result, :success?, result.error
      notification = result.value.fetch(:delivery).notification

      assert Community::NotificationAccess.visible?(notification:, user: @reporter)
      assert_not Community::NotificationAccess.visible?(notification:, user: create_user)

      notification.update!(metadata: notification.metadata.merge("path" => "/app/forum/reports/999999"))
      assert_not Community::NotificationAccess.visible?(notification:, user: @reporter)
      notification.update!(metadata: notification.metadata.merge("path" => forum_report_path(report), "report_id" => report.id + 1))
      assert_not Community::NotificationAccess.visible?(notification:, user: @reporter)
    end

    private

    def create_report
      result = Community::CreateReport.call(
        reporter: @reporter,
        reportable_type: "User",
        reportable_id: @target.id,
        reason_code: "offensive",
        reason_detail: "Reporter supplied detail",
        ip_address: "127.0.0.1"
      )
      assert_predicate result, :success?, result.error
      result.value
    end

    def create_report_for(reporter:, reportable:, detail:)
      result = Community::CreateReport.call(
        reporter:,
        reportable_type: reportable.class.name,
        reportable_id: reportable.id,
        reason_code: "offensive",
        reason_detail: detail,
        ip_address: "127.0.0.1"
      )
      assert_predicate result, :success?, result.error
      result.value
    end

    def decide(report:, key:, expected_version: report.lock_version)
      Community::DecideReport.call(
        report:,
        reviewer: @reviewer,
        desired_status: "actioned",
        internal_note: "internal decision",
        expected_version:,
        idempotency_key: key
      )
    end
  end
end
