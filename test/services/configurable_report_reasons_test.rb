# frozen_string_literal: true

require "test_helper"

class ConfigurableReportReasonsTest < ActiveSupport::TestCase
  def reportable_topic
    author = create_user
    category = Community::Category.create!(name: "C", slug: "c-#{SecureRandom.hex(3)}")
    section = Community::Section.create!(category: category, name: "S", slug: "s-#{SecureRandom.hex(3)}", position: 0)
    Community::Topic.create!(
      public_id: "t_#{SecureRandom.alphanumeric(10)}", section: section, user: author, title: "T",
      status: "published", last_posted_at: Time.current, last_post_user: author, replies_count: 0
    )
  end

  test "reason_options merges built-ins and admin extras" do
    SiteSetting.set("forum.extra_report_reasons", "ddos:Service abuse,doxxing:Posting private info")
    opts = Community::Report.reason_options
    assert_equal "垃圾广告 / 刷屏", opts["spam"]
    assert_equal "Service abuse", opts["ddos"]
    assert_equal "Posting private info", opts["doxxing"]
  end

  test "a report with a configured extra reason code is valid and labels correctly" do
    SiteSetting.set("forum.extra_report_reasons", "ddos:Service abuse")
    report = Community::Report.new(reporter: create_user, reportable: reportable_topic, reason: "abuse", reason_code: "ddos", status: :pending)
    assert report.valid?
    assert_equal "Service abuse", report.reason_label
  end

  test "an unknown reason code is rejected" do
    report = Community::Report.new(reporter: create_user, reportable: reportable_topic, reason: "abuse", reason_code: "nonexistent", status: :pending)
    assert_not report.valid?
  end

  test "a blank reason code is still allowed" do
    report = Community::Report.new(reporter: create_user, reportable: reportable_topic, reason: "free text reason", reason_code: nil, status: :pending)
    assert report.valid?
  end
end
