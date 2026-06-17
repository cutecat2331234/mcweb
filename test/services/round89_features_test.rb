# frozen_string_literal: true

require "test_helper"

class Round89SetSubscriptionLevelTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r89-sub") { |c| c.name = "S" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r89-sub-sec") { |s| s.name = "Sec"; s.position = 0 }
    @topic = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: "Sub level #{SecureRandom.hex(4)}",
      body: "Body content here",
      ip_address: "127.0.0.1"
    ).value
  end

  test "sets watching level on topic" do
    result = Community::SetSubscriptionLevel.call(user: @user, subscribable: @topic, level: "watching")
    assert result.success?
    assert result.value[:watching]
    assert_equal "watching", Community::Subscription.find_by(user: @user, subscribable: @topic).notification_level
  end

  test "sets tracking level on section" do
    result = Community::SetSubscriptionLevel.call(user: @user, subscribable: @section, level: "tracking")
    assert result.success?
    assert_equal "tracking", Community::Subscription.find_by(user: @user, subscribable: @section).notification_level
  end

  test "off unsubscribes" do
    Community::Subscription.subscribe!(@user, @topic, level: "watching")
    result = Community::SetSubscriptionLevel.call(user: @user, subscribable: @topic, level: "off")
    assert result.success?
    refute result.value[:watching]
    assert_nil Community::Subscription.find_by(user: @user, subscribable: @topic)
  end

  test "rejects invalid level" do
    result = Community::SetSubscriptionLevel.call(user: @user, subscribable: @topic, level: "invalid")
    assert result.failure?
    assert_includes result.error, "无效"
  end
end

class Round89BatchTestSavedSearchWebhooksTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    SiteSetting.set("forum.saved_search_webhook_url", "https://example.com/hook")
    @user = create_user
    2.times do |i|
      Community::SavedSearch.create!(user: @user, name: "Batch #{i}", query: "q#{i}", filters: {})
    end
  end

  test "queues webhook for each saved search up to limit" do
    assert_enqueued_jobs 2, only: Community::DispatchSavedSearchWebhookJob do
      result = Community::BatchTestSavedSearchWebhooks.call(user: @user)
      assert result.success?
      assert_equal 2, result.value[:queued]
      assert_equal 2, result.value[:total]
    end
  end

  test "fails when no saved searches" do
    @user.forum_saved_searches.delete_all
    result = Community::BatchTestSavedSearchWebhooks.call(user: @user)
    assert result.failure?
  end
end

class Round89OrderWebhookEventsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    SiteSetting.set("store.order_webhook_url", "https://example.com/store-hook")
  end

  test "dispatch test supports order.cancelled and order.fulfilled" do
    %w[order.cancelled order.fulfilled].each do |event_type|
      assert_enqueued_jobs 1, only: Commerce::DispatchOrderWebhookJob do
        result = Commerce::DispatchTestOrderWebhook.call(event_type: event_type)
        assert result.success?, event_type
        assert_equal event_type, result.value[:event_type]
      end
    end
  end

  test "notify order status change dispatches order.fulfilled event" do
    user = create_user
    order = Commerce::Order.create!(
      public_id: "ord_r89_#{SecureRandom.hex(8)}",
      order_number: "MC#{SecureRandom.hex(4)}",
      user: user,
      status: "fulfilled",
      subtotal_cents: 1000,
      total_cents: 1000,
      currency: "CNY"
    )

    assert_enqueued_jobs 1, only: Commerce::DispatchOrderWebhookJob do
      Commerce::NotifyOrderStatusChange.call(order: order, from_status: "processing")
    end

    job = enqueued_jobs.find { |j| j["job_class"] == "Commerce::DispatchOrderWebhookJob" }
    payload = job["arguments"][1]
    assert_equal "order.fulfilled", payload["event"] || payload[:event]
  end
end

class Round89TopicSubscriptionIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r89-int") { |c| c.name = "I" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r89-int-sec") { |s| s.name = "Sec"; s.position = 0 }
    @topic = Community::CreateTopic.call(
      user: @user,
      section: section,
      title: "Integration #{SecureRandom.hex(4)}",
      body: "Body content here",
      ip_address: "127.0.0.1"
    ).value
    sign_in_as(@user)
  end

  test "patch subscription sets level via dropdown endpoint" do
    patch subscription_forum_topic_path(@topic), params: { level: "normal" }
    assert_redirected_to forum_topic_path(@topic)
    assert_equal "normal", Community::Subscription.find_by(user: @user, subscribable: @topic).notification_level
  end

  test "topic show includes subscription levels props" do
    get forum_topic_path(@topic)
    assert_response :success
    assert_includes response.body, "subscriptionLevels"
    assert_includes response.body, "subscriptionUrl"
  end
end

class Round89PreferencesGuideTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in_as(@user)
  end

  test "preferences page includes notification level guide" do
    get forum_preferences_path
    assert_response :success
    assert_includes response.body, "notificationLevelGuide"
    assert_includes response.body, "跟踪"
  end
end

class Round89BatchTestWebhooksIntegrationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "system.settings.manage")
    SiteSetting.set("forum.saved_search_webhook_url", "https://example.com/hook")
    Community::SavedSearch.create!(user: @admin, name: "Admin search", query: "q", filters: {})
    sign_in_as(@admin)
  end

  test "admin can batch test saved search webhooks" do
    assert_enqueued_jobs 1, only: Community::DispatchSavedSearchWebhookJob do
      post test_all_webhooks_admin_forum_settings_path
    end
    assert_redirected_to admin_forum_settings_path
  end
end

class Round89SubscriptionLevelOptionsTest < ActiveSupport::TestCase
  test "topic section and tag options include off level" do
    %i[topic section tag].each do |context|
      options = Community::SubscriptionLevelOptions.for(context)
      assert options.any? { |o| o[:value] == "off" }, context.to_s
      assert options.any? { |o| o[:value] == "normal" }, context.to_s
    end
  end
end
