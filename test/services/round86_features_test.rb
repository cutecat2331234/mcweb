# frozen_string_literal: true

require "test_helper"

class Round86ForumWebhookTestTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "system.settings.manage")
    SiteSetting.set("forum.saved_search_webhook_url", "https://example.com/forum-hook")
  end

  test "admin can send forum webhook test" do
    sign_in_as(@admin)
    assert_enqueued_jobs 1, only: Community::DispatchSavedSearchWebhookJob do
      post test_webhook_admin_forum_settings_path
    end
    assert_redirected_to admin_forum_settings_path
  end

  test "dispatch test saved search webhook builds match payload" do
    assert_enqueued_jobs 1, only: Community::DispatchSavedSearchWebhookJob do
      result = Community::DispatchTestSavedSearchWebhook.call
      assert result.success?
    end
  end

  test "forum settings page exposes test webhook url" do
    sign_in_as(@admin)
    get admin_forum_settings_path
    assert_response :success
    assert_includes response.body, "testWebhookUrl"
    assert_includes response.body, "forum.saved_search_webhook_url"
  end
end

class Round86SearchHistoryOpmlTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    Community::SearchHistory.record!(user: @user, query: "opml-keyword", filters: {})
  end

  test "search histories opml returns outlines" do
    token = Community::SearchHistoryOpmlToken.generate(@user)
    get forum_search_histories_opml_path(token: token, format: :xml)
    assert_response :success
    assert_includes response.body, "<opml"
    assert_includes response.body, "opml-keyword"
    assert_includes response.body, "search.rss"
  end

  test "search page exposes histories opml url when logged in" do
    sign_in_as(@user)
    get forum_search_path, params: { q: "opml-keyword" }
    assert_response :success
    assert_includes response.body, "searchHistoriesOpmlUrl"
    assert_includes response.body, "search/histories.opml"
  end
end

class Round86SearchHistoryFingerprintTest < ActiveSupport::TestCase
  test "deduplicates by fingerprint regardless of filter key order" do
    user = create_user
    Community::SearchHistory.record!(user: user, query: "x", filters: { "section" => "general", "tag" => "news" })
    Community::SearchHistory.record!(user: user, query: "x", filters: { "tag" => "news", "section" => "general" })
    assert_equal 1, user.forum_search_histories.count
  end
end

class Round86StoreWebhookEventSimulatorTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "system.settings.manage")
    SiteSetting.set("store.order_webhook_url", "https://example.com/hook")
  end

  test "admin can send paid event test webhook" do
    sign_in_as(@admin)
    assert_enqueued_jobs 1, only: Commerce::DispatchOrderWebhookJob do
      post test_webhook_admin_store_settings_path, params: { event: "order.paid" }
    end
    assert_redirected_to admin_store_settings_path
  end

  test "dispatch test order webhook supports event types" do
    result = Commerce::DispatchTestOrderWebhook.call(event_type: "order.shipped")
    assert result.success?
    assert_equal "order.shipped", result.value[:event_type]
  end

  test "store settings exposes event list" do
    sign_in_as(@admin)
    get admin_store_settings_path
    assert_response :success
    assert_includes response.body, "testWebhookEvents"
    assert_includes response.body, "order.paid"
  end
end

class Round86TagTopicEmailTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @section = Community::Section.first || Community::Section.create!(
      name: "R86 Tag",
      slug: "r86-tag-#{SecureRandom.hex(4)}",
      category: Community::Category.find_or_create_by!(slug: "r86-tag-cat") { |c| c.name = "R86 Tag Cat" },
      position: 0
    )
    @author = create_user
    @watcher = create_user
    @tag = Community::Tag.create!(name: "R86Tag#{SecureRandom.hex(3)}", slug: "r86tag#{SecureRandom.hex(3)}")
    Community::Subscription.create!(user: @watcher, subscribable: @tag, notification_level: "watching")
    NotificationPreference.set!(@watcher, channel: "email", notification_type: "forum.tag_topic", enabled: true)
    @topic = Community::Topic.create!(
      title: "Tag Topic",
      section: @section,
      user: @author,
      status: :published
    )
    @topic.tags << @tag
  end

  test "watching tag subscriber receives email" do
    assert_enqueued_jobs 1, only: MailDeliveryJob do
      Community::NotifyTagTopic.call(topic: @topic, tags: [ @tag ])
    end
  end

  test "digest_only mode skips tag topic email" do
    @watcher.update!(forum_watch_email_mode: "digest_only")
    assert_no_enqueued_jobs(only: MailDeliveryJob) do
      Community::NotifyTagTopic.call(topic: @topic, tags: [ @tag ])
    end
  end
end
