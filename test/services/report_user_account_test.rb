# frozen_string_literal: true

require "test_helper"

class ReportUserAccountTest < ActionDispatch::IntegrationTest
  setup do
    @reporter = create_user
    @target = create_user
  end

  test "a member can report another user's account" do
    sign_in_as(@reporter)
    assert_difference -> { Community::Report.where(reportable_type: "User").count }, 1 do
      post forum_reports_path, params: {
        report: { reportable_type: "User", reportable_id: @target.id, reason_code: "offensive", reason_detail: "abusive messages" }
      }
    end
    report = Community::Report.where(reportable_type: "User").last
    assert_equal @target.id, report.reportable_id
    assert_equal @reporter.id, report.reporter_id
    assert_equal "pending", report.status
  end

  test "cannot report your own account" do
    sign_in_as(@reporter)
    assert_no_difference -> { Community::Report.count } do
      post forum_reports_path, params: {
        report: { reportable_type: "User", reportable_id: @reporter.id, reason_code: "spam" }
      }
    end
  end
end
