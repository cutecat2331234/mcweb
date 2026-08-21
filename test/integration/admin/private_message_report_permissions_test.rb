# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  module Forum
    class PrivateMessageReportPermissionsTest < ActionDispatch::IntegrationTest
      include InertiaRails::Minitest

      setup do
        @sender = create_user
        @recipient = create_user
        @normal_target = create_user
        @secret_body = "PRIVATE-REPORT-EVIDENCE-#{SecureRandom.hex(8)}"
        conversation = Community::Conversation.create!
        conversation.participants.create!(user: @sender)
        conversation.participants.create!(user: @recipient)
        @message = conversation.messages.create!(user: @sender, body: @secret_body)

        @private_report = Community::CreateReport.call(
          reporter: @recipient,
          reportable_type: "Community::Message",
          reportable_id: @message.id,
          reason_code: "spam",
          reason_detail: "PRIVATE-REPORT-DETAIL"
        ).value
        @normal_report = Community::CreateReport.call(
          reporter: @recipient,
          reportable_type: "User",
          reportable_id: @normal_target.id,
          reason_code: "offensive",
          reason_detail: "NORMAL-REPORT-DETAIL"
        ).value

        @regular_moderator = create_admin_with("forum.topics.lock")
        @private_reviewer = create_admin_with("forum.conversations.reports.review")
      end

      test "a regular moderator cannot list, reveal, or resolve private-message reports" do
        sign_in_as(@regular_moderator)

        get admin_forum_reports_path
        assert_response :success
        rows = inertia.props.deep_symbolize_keys.fetch(:rows)
        summaries = rows.map { |row| row[:reason] }
        assert summaries.any? { |summary| summary.include?("NORMAL-REPORT-DETAIL") }
        refute summaries.any? { |summary| summary.include?("PRIVATE-REPORT-DETAIL") }
        refute_includes response.body, @secret_body

        get admin_forum_report_path(@private_report)
        assert_response :not_found
        refute_includes response.body, @secret_body

        assert_no_difference -> { AuditLog.by_action("admin.forum_report_evidence_revealed").count } do
          post reveal_evidence_admin_forum_report_path(@private_report)
          assert_response :not_found
        end
        refute_includes response.body, @secret_body

        patch resolve_target_admin_forum_report_path(@private_report), params: { status: "actioned" }
        assert_response :not_found
        assert_predicate @private_report.reload, :pending?
      end

      test "a private-message reviewer sees only private reports and reveal is an audited POST" do
        sign_in_as(@private_reviewer)

        get admin_forum_reports_path
        assert_response :success
        rows = inertia.props.deep_symbolize_keys.fetch(:rows)
        summaries = rows.map { |row| row[:reason] }
        assert summaries.any? { |summary| summary.include?("PRIVATE-REPORT-DETAIL") }
        refute summaries.any? { |summary| summary.include?("NORMAL-REPORT-DETAIL") }
        refute_includes response.body, @secret_body

        get admin_forum_report_path(@normal_report)
        assert_response :not_found

        get admin_forum_report_path(@private_report)
        assert_response :success
        assert_includes response.headers["Cache-Control"], "no-store"
        refute_includes response.body, @secret_body

        assert_difference -> { AuditLog.by_action("admin.forum_report_evidence_revealed").count }, 1 do
          post reveal_evidence_admin_forum_report_path(@private_report)
        end
        assert_response :success
        assert_includes response.headers["Cache-Control"], "no-store"
        assert_includes response.body, @secret_body

        get reveal_evidence_admin_forum_report_path(@private_report)
        assert_response :not_found
      end

      test "private-message report actions promise evidence retention rather than a nonexistent hide" do
        sign_in_as(@private_reviewer)

        get admin_forum_report_path(@private_report)

        assert_response :success
        labels = inertia.props.deep_symbolize_keys.fetch(:actions).pluck(:label)
        assert_includes labels, I18n.t("mcweb.admin.forum.reports.action_uphold_private_message")
        assert_includes labels, I18n.t("mcweb.admin.forum.reports.action_uphold_all_private_messages")
        refute_includes labels, I18n.t("mcweb.admin.forum.reports.action_agree")
        refute_includes labels, I18n.t("mcweb.admin.forum.reports.action_resolve_target_action")

        patch admin_forum_report_path(@private_report), params: {
          report: { status: "actioned", review_note: "Confirmed policy violation" }
        }

        assert_redirected_to admin_forum_report_path(@private_report)
        assert_predicate @private_report.reload, :actioned?
        assert Community::Message.exists?(@message.id)
        assert_equal @secret_body, @message.reload.body
        assert_predicate @private_report.evidence, :persisted?
        audit = AuditLog.by_action("admin.forum_report_reviewed")
          .find_by!(resource_type: "Community::Report", resource_id: @private_report.id)
        assert_equal "upheld_private_message_evidence_retained", audit.metadata.fetch("disposition")
      end

      test "private-message workbench cases target the sender without exposing message content" do
        grant_permission(@private_reviewer, "forum.users.warn")
        synced = Community::ModerationWorkbench::SyncCases.call
        assert_predicate synced, :success?, synced.error
        moderation_case = Community::ModerationCase.find_by!(
          source_type: "Community::Report",
          source_id: @private_report.id
        )

        assert_equal @sender.id, moderation_case.target_user_id
        detail = Community::ModerationWorkbench::CaseDetail.call(
          actor: @private_reviewer,
          moderation_case: moderation_case
        )
        assert_predicate detail, :success?, detail.error
        assert_equal @sender.username, detail.value.dig(:target_user, :username)
        assert_includes detail.value.fetch(:available_actions), "warn_user"
        assert_equal true, detail.value.dig(:evidence, :restricted)
        refute_includes JSON.generate(detail.value), @secret_body
      end

      test "bulk upholding private-message reports retains the message and immutable evidence" do
        sign_in_as(@private_reviewer)

        patch resolve_target_admin_forum_report_path(@private_report), params: { status: "actioned" }

        assert_redirected_to admin_forum_reports_path
        assert_predicate @private_report.reload, :actioned?
        assert Community::Message.exists?(@message.id)
        assert_equal @secret_body, @message.reload.body
        assert_predicate @private_report.evidence, :digest_valid?
        audit = AuditLog.by_action("admin.forum_reports_bulk_resolved")
          .find_by!(resource_type: "Community::Message", resource_id: @message.id)
        assert_equal "upheld_private_message_evidence_retained", audit.metadata.fetch("disposition")
      end

      private

      def create_admin_with(permission)
        admin = create_user(account_type: "admin")
        grant_permission(admin, "admin.access")
        grant_permission(admin, permission)
        grant_admin_module(admin, "forum")
        admin
      end
    end
  end
end
