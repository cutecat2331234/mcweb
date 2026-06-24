# frozen_string_literal: true

require "test_helper"

class FlagAbuseThresholdTest < ActiveSupport::TestCase
  setup do
    SiteSetting.set("forum.report_auto_hide_threshold", "2")
    SiteSetting.set("forum.flag_abuse_threshold", "3")
    @author = create_user
    category = Community::Category.create!(name: "C", slug: "c-#{SecureRandom.hex(3)}")
    @section = Community::Section.create!(category: category, name: "S", slug: "s-#{SecureRandom.hex(3)}", position: 0)
    @post = make_post
  end

  def make_post
    topic = Community::Topic.create!(
      public_id: "t_#{SecureRandom.alphanumeric(10)}", section: @section, user: @author, title: "T",
      status: "published", last_posted_at: Time.current, last_post_user: @author, replies_count: 0
    )
    Community::Post.create!(topic: topic, user: @author, floor_number: 1, body: "b", status: "published")
  end

  test "discounts flags from repeat false-flaggers toward auto-hide" do
    credible = create_user
    abuser = create_user
    3.times { Community::Report.create!(reporter: abuser, reportable: make_post, reason: "x", status: :dismissed) }

    Community::Report.create!(reporter: credible, reportable: @post, reason: "x", status: :pending)
    last = Community::Report.create!(reporter: abuser, reportable: @post, reason: "x", status: :pending)

    Community::CheckReportThreshold.call(report: last)
    assert_equal "published", @post.reload.status
  end

  test "credible reporters still trigger auto-hide" do
    Community::Report.create!(reporter: create_user, reportable: @post, reason: "x", status: :pending)
    last = Community::Report.create!(reporter: create_user, reportable: @post, reason: "x", status: :pending)

    Community::CheckReportThreshold.call(report: last)
    assert_equal "hidden", @post.reload.status
  end
end
