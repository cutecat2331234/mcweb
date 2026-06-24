# frozen_string_literal: true

require "test_helper"

class ReportUserAdminReviewTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "forum.topics.lock")
    grant_admin_module(@admin, "forum")
    @target = create_user
    reporter = create_user
    @report = Community::Report.create!(reporter: reporter, reportable: @target, reason: "harassment", status: :pending)
    sign_in_as(@admin)
  end

  test "admin report review renders a reported member with a profile link" do
    get admin_forum_report_path(@report)
    assert_response :success
    # The User target now resolves to the member's username (target_user label +
    # the view-profile action href), instead of a bare "User #id".
    assert_match @target.username, response.body
    assert_no_match(/User ##{@report.reportable_id}/, response.body)
  end
end
