# frozen_string_literal: true

require "test_helper"

class Round97SearchActiveFiltersTest < ActiveSupport::TestCase
  setup do
    category = Community::Category.find_or_create_by!(slug: "r97-cat") { |c| c.name = "R97" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r97-sec") { |s| s.name = "Sec"; s.position = 0 }
    @tag = Community::Tag.find_or_create_by!(slug: "r97-tag") { |t| t.name = "R97Tag" }
  end

  test "builds structured filter chips" do
    chips = Community::SearchActiveFilters.call(
      query: "ruby -spam",
      section: @section.slug,
      tag: @tag.slug,
      author: "alice",
      solved: "solved"
    )
    assert chips.any? { |c| c[:param] == "q" && c[:label].include?("ruby") }
    assert chips.any? { |c| c[:param] == "section" }
    assert chips.any? { |c| c[:param] == "tag" }
    assert chips.any? { |c| c[:param] == "author" }
    assert chips.any? { |c| c[:param] == "exclude" && c[:value] == "spam" }
  end
end

class Round97SearchActiveFiltersIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in_as(@user)
  end

  test "search passes active filters" do
    get forum_search_path(q: "test", author: "bob", solved: "solved")
    assert_response :success
    assert_includes response.body, "activeFilters"
    assert_includes response.body, "作者：bob"
  end
end

class Round97DigestGroupingTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    Notification.create!(user: @user, notification_type: "forum.reaction", title: "R1", body: "b")
    Notification.create!(user: @user, notification_type: "forum.reaction", title: "R2", body: "b")
    Notification.create!(user: @user, notification_type: "forum.badge", title: "Badge", body: "b")
    @notifications = @user.notifications.order(:id)
  end

  test "groups digest notifications by type" do
    sections = Community::GroupDigestNotifications.call(@notifications)
    assert_equal 2, sections.size
    reaction = sections.find { |s| s[:type] == "forum.reaction" }
    assert_equal 2, reaction[:notifications].size
  end
end

class Round97PollClosedBannerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r97-poll") { |c| c.name = "P" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r97-poll-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: @user,
      title: "Poll banner",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @user,
      replies_count: 0
    )
    Community::Post.create!(topic: @topic, user: @user, floor_number: 1, body: "Hi", status: "published")
    Community::Poll.create!(topic: @topic, question: "Q?", options: %w[A B], closes_at: 1.hour.ago)
    sign_in_as(@user)
  end

  test "closed poll includes closed_at" do
    get forum_topic_path(@topic)
    assert_response :success
    assert_includes response.body, "closed_at"
  end
end

class Round97OrderStatusTabsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "store.orders.read")
    @user = create_user
    Commerce::Order.create!(
      public_id: "ord_r97_#{SecureRandom.hex(8)}",
      order_number: "PAID#{SecureRandom.hex(4)}",
      user: @user,
      status: "paid",
      subtotal_cents: 900,
      total_cents: 900,
      currency: "CNY"
    )
    sign_in_as(@admin)
  end

  test "hides zero-count status tabs" do
    get admin_store_orders_path
    assert_response :success
    refute_includes response.body, "status=pending"
  end
end

class Round97WebhookStatusTabsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "system.settings.manage")
    Commerce::OrderWebhookDelivery.create!(
      order_public_id: "ord_test",
      event_type: "order.paid",
      status: "failed",
      url: "https://example.com/hook",
      request_payload: {},
      response_code: 500
    )
    sign_in_as(@admin)
  end

  test "webhook status tabs include counts" do
    get admin_store_webhook_deliveries_path
    assert_response :success
    assert_includes response.body, '"count"'
  end
end
