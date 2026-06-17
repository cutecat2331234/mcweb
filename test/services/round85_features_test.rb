# frozen_string_literal: true

require "test_helper"

class Round85SearchHistoryTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @section = Community::Section.first || Community::Section.create!(
      name: "R85 Section",
      slug: "r85-sec-#{SecureRandom.hex(4)}",
      category: Community::Category.find_or_create_by!(slug: "r85-cat") { |c| c.name = "R85 Cat" },
      position: 0
    )
    @keyword = "R85History#{SecureRandom.hex(4)}"
    @topic = Community::Topic.create!(
      title: @keyword,
      section: @section,
      user: @user,
      status: :published
    )
    Community::Post.create!(
      topic: @topic,
      user: @user,
      body: "body",
      floor_number: 1,
      status: :published
    )
  end

  test "logged in search records history" do
    sign_in_as(@user)
    get forum_search_path, params: { q: @keyword }
    assert_response :success
    assert_includes response.body, "searchHistories"
    assert_equal 1, @user.forum_search_histories.count
    assert_equal @keyword, @user.forum_search_histories.last.query
  end

  test "search history deduplicates same query" do
    sign_in_as(@user)
    2.times { get forum_search_path, params: { q: @keyword } }
    assert_equal 1, @user.forum_search_histories.count
  end

  test "user can delete search history entry" do
    sign_in_as(@user)
    entry = Community::SearchHistory.record!(user: @user, query: "x", filters: {})
    delete forum_search_history_path(entry)
    assert_redirected_to forum_search_path
    assert_empty @user.forum_search_histories.reload
  end

  test "user can clear search history" do
    sign_in_as(@user)
    Community::SearchHistory.record!(user: @user, query: "a", filters: {})
    Community::SearchHistory.record!(user: @user, query: "b", filters: {})
    delete forum_clear_search_histories_path
    assert_redirected_to forum_search_path
    assert_empty @user.forum_search_histories.reload
  end
end

class Round85DigestMarkReadTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = create_user(forum_digest_frequency: "daily")
    Notification.notify!(
      user: @user,
      notification_type: "forum.topic_reply",
      title: "Test",
      body: "body"
    )
  end

  test "digest marks notifications as read" do
    assert_enqueued_jobs 1, only: MailDeliveryJob do
      result = Community::SendForumDigest.call(user: @user)
      assert result.success?
      assert result.value[:sent]
    end
    assert @user.notifications.all?(&:read?)
  end
end

class Round85StoreWebhookTestTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "system.settings.manage")
    SiteSetting.set("store.order_webhook_url", "https://example.com/hook")
  end

  test "admin can send test webhook from store settings" do
    sign_in_as(@admin)
    assert_enqueued_jobs 1, only: Commerce::DispatchOrderWebhookJob do
      post test_webhook_admin_store_settings_path
    end
    assert_redirected_to admin_store_settings_path
  end

  test "dispatch test order webhook builds order.test payload" do
    assert_enqueued_jobs 1, only: Commerce::DispatchOrderWebhookJob do
      result = Commerce::DispatchTestOrderWebhook.call
      assert result.success?
    end
  end

  test "store settings page exposes test webhook url" do
    sign_in_as(@admin)
    get admin_store_settings_path
    assert_response :success
    assert_includes response.body, "testWebhookUrl"
  end
end

class Round85WebhookAlertSplitTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @previous_forum = SiteSetting.get("webhook.failure_alert_forum_threshold")
    @previous_store = SiteSetting.get("webhook.failure_alert_store_threshold")
    @previous_email = SiteSetting.get("webhook.failure_alert_email")
    SiteSetting.set("webhook.failure_alert_forum_threshold", "2")
    SiteSetting.set("webhook.failure_alert_store_threshold", "10")
    SiteSetting.set("webhook.failure_alert_email", "admin@example.com")
    SiteSetting.set("webhook.failure_alert_last_sent_at", "")
  end

  teardown do
    SiteSetting.set("webhook.failure_alert_forum_threshold", @previous_forum || "5")
    SiteSetting.set("webhook.failure_alert_store_threshold", @previous_store || "5")
    SiteSetting.set("webhook.failure_alert_email", @previous_email || "")
  end

  test "alerts only when forum threshold exceeded" do
    user = create_user
    search = user.forum_saved_searches.create!(name: "A", query: "x", filters: {})
    2.times do
      Community::SavedSearchWebhookDelivery.create!(
        saved_search: search,
        event_type: "saved_search.match",
        url: "https://example.com/h",
        status: "failed"
      )
    end

    assert_emails 1 do
      result = WebhookFailureAlertCheck.call
      assert result.success?
      assert result.value[:forum_alert]
      assert_not result.value[:store_alert]
    end
  end
end

class Round85SearchHistoryLimitTest < ActiveSupport::TestCase
  test "trims history to limit" do
    user = create_user
    (Community::SearchHistory::LIMIT + 3).times do |i|
      Community::SearchHistory.record!(user: user, query: "q#{i}", filters: {})
    end
    assert_equal Community::SearchHistory::LIMIT, user.forum_search_histories.count
  end
end
