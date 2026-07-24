# frozen_string_literal: true

require "test_helper"

class ReportEventTest < ActionDispatch::IntegrationTest
  setup do
    category = Community::Category.find_or_create_by!(slug: "rep-cat") { |c| c.name = "R" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "rep-sec") do |s|
      s.name = "R"
      s.position = 0
    end
    @author = create_user(username: "repauthor")
    @reporter = create_user(username: "repreporter")
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}", section: @section, user: @author,
      title: "Reportable", status: "published", last_posted_at: Time.current, last_post_user: @author, replies_count: 0
    )
    @post = Community::Post.create!(topic: @topic, user: @author, floor_number: 1, body: "OP", status: "published")
  end

  test "creating a report publishes forum.report.created" do
    sign_in_as(@reporter)
    events = []
    sub = Mcweb::Events.subscribe("forum.report.created") { |p| events << p }

    assert_difference -> { Community::Report.count }, 1 do
      post forum_reports_path, params: {
        report: { reportable_type: "Community::Post", reportable_id: @post.id, reason_code: "spam" }
      }
    end

    assert_equal 1, events.size
    assert_equal @reporter.id, events.first[:reporter].id
    assert_equal @post.id, events.first[:report].reportable_id
  ensure
    Mcweb::Events.unsubscribe(sub)
  end
end
