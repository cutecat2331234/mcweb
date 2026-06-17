# frozen_string_literal: true

require "test_helper"

class Round87SearchFeedsOpmlTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    Community::SearchHistory.record!(user: @user, query: "combined-keyword", filters: {})
    Community::SavedSearch.create!(
      user: @user,
      name: "My Saved",
      query: "saved-q",
      filters: {}
    )
  end

  test "search feeds opml combines saved searches and histories" do
    token = Community::SearchFeedsOpmlToken.generate(@user)
    get forum_search_feeds_opml_path(token: token, format: :xml)
    assert_response :success
    assert_includes response.body, "<opml"
    assert_includes response.body, "保存的搜索"
    assert_includes response.body, "搜索历史"
    assert_includes response.body, "combined-keyword"
    assert_includes response.body, "My Saved"
  end

  test "search page exposes combined opml url" do
    sign_in_as(@user)
    get forum_search_path
    assert_response :success
    assert_includes response.body, "searchFeedsOpmlUrl"
  end
end

class Round87ForumWebhookSavedSearchTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "system.settings.manage")
    SiteSetting.set("forum.saved_search_webhook_url", "https://example.com/forum-hook")
    @search = Community::SavedSearch.create!(
      user: @admin,
      name: "Admin Search",
      query: "webhook-test",
      filters: {}
    )
  end

  test "dispatch test webhook with saved search uses real payload" do
    assert_enqueued_jobs 1, only: Community::DispatchSavedSearchWebhookJob do
      result = Community::DispatchTestSavedSearchWebhook.call(saved_search: @search)
      assert result.success?
      assert_equal @search.id, result.value[:saved_search_id]
    end
  end

  test "admin can test webhook with saved search id" do
    sign_in_as(@admin)
    assert_enqueued_jobs 1, only: Community::DispatchSavedSearchWebhookJob do
      post test_webhook_admin_forum_settings_path, params: { saved_search_id: @search.id }
    end
    assert_redirected_to admin_forum_settings_path
  end

  test "forum settings exposes saved searches for test" do
    sign_in_as(@admin)
    get admin_forum_settings_path
    assert_response :success
    assert_includes response.body, "savedSearchesForTest"
    assert_includes response.body, "Admin Search"
  end
end

class Round87WebhookTestDeliveryStatusTest < ActiveSupport::TestCase
  test "forum last test delivery" do
    Community::SavedSearchWebhookDelivery.create!(
      event_type: "saved_search.match",
      url: "https://example.com/hook",
      status: "success",
      response_code: 200,
      request_payload: { "event" => "saved_search.match", "test" => true }
    )

    last = WebhookTestDeliveryStatus.forum_last
    assert_equal "saved_search.match", last[:event_type]
    assert_equal "success", last[:status]
    assert_equal 200, last[:response_code]
  end

  test "store last test delivery" do
    Commerce::OrderWebhookDelivery.create!(
      event_type: "order.test",
      order_public_id: "test_abc123",
      url: "https://example.com/store-hook",
      status: "failed",
      response_code: 500,
      request_payload: { "event" => "order.test", "test" => true }
    )

    last = WebhookTestDeliveryStatus.store_last
    assert_equal "order.test", last[:event_type]
    assert_equal "failed", last[:status]
  end
end

class Round87WebhookStatsByEventTest < ActiveSupport::TestCase
  test "store stats grouped by event type" do
    Commerce::OrderWebhookDelivery.create!(
      event_type: "order.test",
      order_public_id: "test_1",
      url: "https://example.com/hook",
      status: "success",
      request_payload: {}
    )
    Commerce::OrderWebhookDelivery.create!(
      event_type: "order.paid",
      order_public_id: "ord_1",
      url: "https://example.com/hook",
      status: "failed",
      request_payload: {}
    )

    stats = WebhookDeliveryStats.summary
    by_event = stats[:store_by_event]
    test_row = by_event.find { |r| r[:event_type] == "order.test" }
    paid_row = by_event.find { |r| r[:event_type] == "order.paid" }
    assert_equal 1, test_row[:success]
    assert_equal 1, paid_row[:failed]
  end
end

class Round87MentionDigestExclusionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @author = create_user
    @mentioned = create_user(username: "mention_digest_#{SecureRandom.hex(3)}")
    @mentioned.update!(forum_digest_frequency: "daily")
    category = Community::Category.find_or_create_by!(slug: "r87-digest") { |c| c.name = "D" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r87-digest-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(
      user: @author, section: section, title: "Digest", body: "OP", ip_address: "127.0.0.1"
    ).value
    @post = @topic.posts.first
    NotificationPreference.set!(@mentioned, channel: "email", notification_type: "forum.mention", enabled: true)
    NotificationPreference.set!(@mentioned, channel: "in_app", notification_type: "forum.mention", enabled: true)
  end

  test "mention instant email skipped when user receives digest" do
    assert_no_enqueued_jobs(only: MailDeliveryJob) do
      Community::ProcessMentions.call(
        body: "Hello @#{@mentioned.username}",
        author: @author,
        post: @post,
        topic: @topic
      )
    end
    assert Notification.exists?(user: @mentioned, notification_type: "forum.mention")
  end

  test "mention instant email sent when digest disabled" do
    @mentioned.update!(forum_digest_frequency: "none")

    assert_enqueued_jobs 1, only: MailDeliveryJob do
      Community::ProcessMentions.call(
        body: "Hello @#{@mentioned.username}",
        author: @author,
        post: @post,
        topic: @topic
      )
    end
  end
end

class Round87InstantEmailDeliveryTest < ActiveSupport::TestCase
  test "defer_to_digest for mention when weekly digest enabled" do
    user = create_user
    user.update!(forum_digest_frequency: "weekly")
    assert Community::InstantEmailDelivery.defer_to_digest?(user, notification_type: "forum.mention")
    refute Community::InstantEmailDelivery.defer_to_digest?(user, notification_type: "commerce.order_paid")
  end
end
