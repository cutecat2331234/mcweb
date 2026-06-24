# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class FlagQueuePriorityTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "forum.topics.lock")
    grant_admin_module(@admin, "forum")

    author = create_user
    category = Community::Category.create!(name: "C", slug: "c-#{SecureRandom.hex(3)}")
    @section = Community::Section.create!(category: category, name: "S", slug: "s-#{SecureRandom.hex(3)}", position: 0)
    hot = make_post(author)
    mild = make_post(author)

    2.times { Community::Report.create!(reporter: create_user, reportable: hot, reason: "spam", status: :pending) }
    Community::Report.create!(reporter: create_user, reportable: mild, reason: "spam", status: :pending)
    sign_in_as(@admin)
  end

  def make_post(user)
    topic = Community::Topic.create!(
      public_id: "t_#{SecureRandom.alphanumeric(10)}", section: @section, user: user, title: "T",
      status: "published", last_posted_at: Time.current, last_post_user: user, replies_count: 0
    )
    Community::Post.create!(topic: topic, user: user, floor_number: 1, body: "b", status: "published")
  end

  test "orders the flag queue with the most-flagged target first" do
    get admin_forum_reports_path
    assert_response :success

    rows = inertia.props.deep_symbolize_keys[:rows]
    assert_equal "2", rows.first[:flags]
  end
end
