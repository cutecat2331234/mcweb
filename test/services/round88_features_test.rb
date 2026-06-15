# frozen_string_literal: true

require "test_helper"

class Round88NormalNotificationLevelTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @author = create_user
    @normal_user = create_user
    @watcher = create_user
    category = Community::Category.find_or_create_by!(slug: "r88-normal") { |c| c.name = "N" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r88-normal-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @author, section: section, title: "Normal", body: "OP", ip_address: "127.0.0.1").value
    Community::Subscription.subscribe!(@normal_user, @topic, level: "normal")
    Community::Subscription.subscribe!(@watcher, @topic, level: "watching")
  end

  test "normal level skips reply notification for non-participant" do
    replier = create_user
    result = Community::CreatePost.call(user: replier, topic: @topic, body: "hello", ip_address: "127.0.0.1")
    assert result.success?

    assert_not Notification.exists?(user: @normal_user, notification_type: "forum.topic_reply")
    assert Notification.exists?(user: @watcher, notification_type: "forum.topic_reply")
  end

  test "normal level notifies participant on reply" do
    Community::CreatePost.call(user: @normal_user, topic: @topic, body: "I posted", ip_address: "127.0.0.1")
    replier = create_user
    Community::CreatePost.call(user: replier, topic: @topic, body: "reply", ip_address: "127.0.0.1")

    assert Notification.exists?(user: @normal_user, notification_type: "forum.topic_reply")
  end

  test "normal level notifies when mentioned in reply" do
    replier = create_user
    Community::CreatePost.call(
      user: replier,
      topic: @topic,
      body: "Hey @#{@normal_user.username}",
      ip_address: "127.0.0.1"
    )

    assert Notification.exists?(user: @normal_user, notification_type: "forum.topic_reply")
  end
end

class Round88SectionNormalLevelTest < ActiveSupport::TestCase
  setup do
    @author = create_user
    @normal_user = create_user
    category = Community::Category.find_or_create_by!(slug: "r88-sec") { |c| c.name = "S" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r88-sec-sub") { |s| s.name = "Sub"; s.position = 0 }
    Community::Subscription.subscribe!(@normal_user, @section, level: "normal")
  end

  test "normal section subscription skips new topic notification" do
    result = Community::CreateTopic.call(
      user: @author,
      section: @section,
      title: "New #{SecureRandom.hex(4)}",
      body: "Body content here",
      ip_address: "127.0.0.1"
    )
    assert result.success?, result.error || result.errors.inspect
    Community::NotifySectionTopic.call(topic: result.value)

    assert_not Notification.exists?(user: @normal_user, notification_type: "forum.section_topic")
  end
end

class Round88OrderRefundedWebhookTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    SiteSetting.set("store.order_webhook_url", "https://example.com/store-hook")
  end

  test "dispatch test supports order.refunded" do
    assert_enqueued_jobs 1, only: Commerce::DispatchOrderWebhookJob do
      result = Commerce::DispatchTestOrderWebhook.call(event_type: "order.refunded")
      assert result.success?
      assert_equal "order.refunded", result.value[:event_type]
    end
  end
end

class Round88WebhookKindFilterTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "system.settings.manage")
    Community::SavedSearchWebhookDelivery.create!(
      event_type: "saved_search.match",
      url: "https://example.com/hook",
      status: "success",
      response_code: 200,
      request_payload: { "event" => "saved_search.match", "test" => true, "search_name" => "Test Hook" }
    )
    Community::SavedSearchWebhookDelivery.create!(
      saved_search: Community::SavedSearch.create!(user: @admin, name: "Real", query: "q", filters: {}),
      event_type: "saved_search.match",
      url: "https://example.com/hook",
      status: "success",
      response_code: 200,
      request_payload: { "event" => "saved_search.match", "search_name" => "Real" }
    )
  end

  test "forum webhook deliveries filter by test kind" do
    sign_in_as(@admin)
    get admin_forum_webhook_deliveries_path(kind: "test")
    assert_response :success
    assert_includes response.body, "kindTabs"
    assert_includes response.body, "Test Hook"
  end
end

class Round88WebhookTestStatusTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "system.settings.manage")
  end

  test "forum webhook test status returns json" do
    sign_in_as(@admin)
    get webhook_test_status_admin_forum_settings_path
    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("lastTestWebhook")
  end

  test "store webhook test status returns json" do
    sign_in_as(@admin)
    get webhook_test_status_admin_store_settings_path
    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("lastTestWebhook")
  end
end

class Round88SearchFeedsOpmlLimitTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    SiteSetting.set("forum.search_feeds_opml_saved_limit", "1")
    2.times do |i|
      Community::SavedSearch.create!(user: @user, name: "Saved #{i}", query: "q#{i}", filters: {})
    end
  end

  test "search feeds opml respects saved limit setting" do
    token = Community::SearchFeedsOpmlToken.generate(@user)
    get forum_search_feeds_opml_path(token: token, format: :xml)
    assert_response :success
    assert_includes response.body, "Saved 1"
    assert_not_includes response.body, "Saved 0"
  end
end

class Round88WatchEmailDigestExclusionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @author = create_user
    @watcher = create_user
    @watcher.update!(forum_digest_frequency: "daily", forum_watch_email_mode: "instant")
    category = Community::Category.find_or_create_by!(slug: "r88-digest-watch") { |c| c.name = "D" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r88-digest-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @author, section: section, title: "Digest", body: "OP", ip_address: "127.0.0.1").value
    Community::Subscription.where(user: @author, subscribable: @topic).delete_all
    Community::Subscription.subscribe!(@watcher, @topic, level: "watching")
    NotificationPreference.set!(@watcher, channel: "email", notification_type: "forum.topic_reply", enabled: true)
  end

  test "watching email skipped when digest enabled" do
    refute Community::NotificationLevelFilter.deliver_watch_email?(
      level: "watching",
      user: @watcher,
      notification_type: "forum.topic_reply"
    )

    replier = create_user
    post = Community::Post.create!(
      topic: @topic,
      user: replier,
      body: "reply body text",
      status: :published,
      floor_number: @topic.posts.count + 1
    )

    assert_no_enqueued_jobs(only: MailDeliveryJob) do
      Community::NotifyTopicReply.call(post: post)
    end
  end
end
