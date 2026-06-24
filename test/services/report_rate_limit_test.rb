# frozen_string_literal: true

require "test_helper"

class ReportRateLimitTest < ActionDispatch::IntegrationTest
  setup do
    SiteSetting.set("forum.max_reports_per_hour", "2")
    @reporter = create_user
    author = create_user
    category = Community::Category.create!(name: "C", slug: "c-#{SecureRandom.hex(3)}")
    section = Community::Section.create!(category: category, name: "S", slug: "s-#{SecureRandom.hex(3)}", position: 0)
    @posts = Array.new(3) do |i|
      topic = Community::Topic.create!(
        public_id: "t_#{SecureRandom.alphanumeric(10)}",
        section: section, user: author, title: "T#{i}", status: "published",
        last_posted_at: Time.current, last_post_user: author, replies_count: 0
      )
      Community::Post.create!(topic: topic, user: author, floor_number: 1, body: "post #{i}", status: "published")
    end
    sign_in_as(@reporter)
  end

  def submit_report(target)
    post forum_reports_path, params: {
      report: { reportable_type: "Community::Post", reportable_id: target.id, reason: "spam content" }
    }
  end

  test "rate-limits report submissions per hour" do
    submit_report(@posts[0])
    submit_report(@posts[1])
    assert_equal 2, Community::Report.where(reporter: @reporter).count

    submit_report(@posts[2]) # exceeds the limit of 2/hour
    assert_equal 2, Community::Report.where(reporter: @reporter).count
  end
end
