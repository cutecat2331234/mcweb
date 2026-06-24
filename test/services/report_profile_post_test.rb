# frozen_string_literal: true

require "test_helper"

class ReportProfilePostTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user
    @poster = create_user
    @reporter = create_user
    @post = Community::ProfilePost.create!(profile_user: @owner, author: @poster, body: "wall message", status: "published")
  end

  test "a member can report a profile-wall post" do
    sign_in_as(@reporter)
    assert_difference "Community::Report.count", 1 do
      post forum_reports_path, params: {
        report: { reportable_type: "Community::ProfilePost", reportable_id: @post.id, reason: "spam content" }
      }
    end
    assert_equal @post, Community::Report.last.reportable
  end

  test "agree-and-hide hides a reported profile post" do
    result = Community::HideReportable.call(reportable: @post)
    assert result.success?
    assert_equal "hidden", @post.reload.status
  end

  test "clearing the hide republishes a profile post when no reports remain" do
    @post.update!(status: :hidden)
    assert Community::ClearReportableHide.call(reportable: @post).success?
    assert_equal "published", @post.reload.status
  end
end
