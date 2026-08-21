# frozen_string_literal: true

require "test_helper"

class PrivateMessageReportWorkbenchPolicyTest < ActiveSupport::TestCase
  setup do
    sender = create_user
    recipient = create_user
    normal_target = create_user
    conversation = Community::Conversation.create!
    conversation.participants.create!(user: sender)
    conversation.participants.create!(user: recipient)
    message = conversation.messages.create!(user: sender, body: "Restricted workbench evidence")

    @private_report = Community::CreateReport.call(
      reporter: recipient,
      reportable_type: "Community::Message",
      reportable_id: message.id,
      reason_code: "spam"
    ).value
    @normal_report = Community::CreateReport.call(
      reporter: recipient,
      reportable_type: "User",
      reportable_id: normal_target.id,
      reason_code: "offensive"
    ).value
    @private_case = create_case(@private_report)
    @normal_case = create_case(@normal_report)

    @regular_moderator = create_user
    grant_permission(@regular_moderator, "forum.topics.lock")
    @private_reviewer = create_user
    grant_permission(@private_reviewer, "forum.conversations.reports.review")
  end

  test "normal and private report capabilities produce disjoint workbench scopes" do
    regular_policy = Community::ModerationWorkbench::Policy.new(@regular_moderator)
    assert_includes regular_policy.visible_scope.pluck(:id), @normal_case.id
    refute_includes regular_policy.visible_scope.pluck(:id), @private_case.id
    refute regular_policy.visible?(@private_case)

    private_policy = Community::ModerationWorkbench::Policy.new(@private_reviewer)
    assert_includes private_policy.visible_scope.pluck(:id), @private_case.id
    refute_includes private_policy.visible_scope.pluck(:id), @normal_case.id
    assert private_policy.visible?(@private_case)
    refute private_policy.visible?(@normal_case)
    refute private_policy.evidence_visible?(@private_case)

    assignable_ids = private_policy.assignable_staff(@private_case).map(&:id)
    assert_includes assignable_ids, @private_reviewer.id
    refute_includes assignable_ids, @regular_moderator.id
  end

  private

  def create_case(report)
    Community::ModerationCase.create!(
      source: report,
      source_kind: "report",
      status: "open",
      priority: "normal",
      risk_level: "medium",
      target_user: report.reportable.respond_to?(:user) ? report.reportable.user : report.reportable,
      title: "Report case #{report.id}",
      summary: "Permission boundary fixture",
      source_updated_at: report.updated_at
    )
  end
end
