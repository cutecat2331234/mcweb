# frozen_string_literal: true

require "test_helper"

class Round84AdHocSearchOpmlTest < ActionDispatch::IntegrationTest
  setup do
    @section = Community::Section.first || Community::Section.create!(
      name: "R84 Section",
      slug: "r84-sec-#{SecureRandom.hex(4)}",
      category: Community::Category.find_or_create_by!(slug: "r84-cat") { |c| c.name = "R84 Cat" },
      position: 0
    )
    @user = create_user
    @keyword = "R84Opml#{SecureRandom.hex(4)}"
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

  test "ad hoc search opml returns valid opml" do
    opml_params = { q: @keyword }
    token = Community::SearchRssToken.generate(opml_params)
    get forum_search_opml_path(opml_params.merge(token: token, format: :xml))
    assert_response :success
    assert_includes response.body, "<opml"
    assert_includes response.body, "search.rss"
    assert_includes response.body, @keyword
  end

  test "search page exposes search opml url" do
    get forum_search_path, params: { q: @keyword }
    assert_response :success
    assert_includes response.body, "searchOpmlUrl"
    assert_includes response.body, "search.opml"
  end
end

class Round84WebhookFailureAlertTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper
  setup do
    @previous_threshold = SiteSetting.get("webhook.failure_alert_threshold")
    @previous_email = SiteSetting.get("webhook.failure_alert_email")
    @previous_cooldown = SiteSetting.get("webhook.failure_alert_last_sent_at")
    SiteSetting.set("webhook.failure_alert_threshold", "2")
    SiteSetting.set("webhook.failure_alert_forum_threshold", "2")
    SiteSetting.set("webhook.failure_alert_store_threshold", "0")
    SiteSetting.set("webhook.failure_alert_email", "admin-alert@example.com")
    SiteSetting.set("webhook.failure_alert_last_sent_at", "")
  end

  teardown do
    SiteSetting.set("webhook.failure_alert_threshold", @previous_threshold || "5")
    SiteSetting.set("webhook.failure_alert_email", @previous_email || "")
    SiteSetting.set("webhook.failure_alert_last_sent_at", @previous_cooldown || "")
  end

  test "sends alert when failures exceed threshold" do
    user = create_user
    search = user.forum_saved_searches.create!(name: "A", query: "x", filters: {})
    2.times do
      Community::SavedSearchWebhookDelivery.create!(
        saved_search: search,
        event_type: "saved_search.match",
        url: "https://example.com/h",
        status: "failed",
        response_code: 500
      )
    end

    assert_emails 1 do
      result = WebhookFailureAlertCheck.call
      assert result.success?
      assert result.value[:sent]
    end
  end

  test "skips alert when below threshold" do
    assert_emails 0 do
      result = WebhookFailureAlertCheck.call
      assert result.success?
      assert_equal :below_threshold, result.value[:skipped]
    end
  end

  test "recurring config schedules webhook failure alert job" do
    content = File.read(Rails.root.join("config/sidekiq_cron.yml"))
    assert_includes content, "WebhookFailureAlertJob"
    assert_includes content, "Website::GenerateSitemapJob"
  end

  test "forum settings include webhook alert keys" do
    content = File.read(Rails.root.join("app/controllers/admin/forum/settings_controller.rb"))
    assert_includes content, "webhook.failure_alert_threshold"
    assert_includes content, "webhook.failure_alert_email"
  end
end

class Round84WatchEmailModeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @section = Community::Section.first || Community::Section.create!(
      name: "R84 Watch",
      slug: "r84-watch-#{SecureRandom.hex(4)}",
      category: Community::Category.find_or_create_by!(slug: "r84-watch-cat") { |c| c.name = "R84 Watch Cat" },
      position: 0
    )
    @author = create_user
    @watcher = create_user
    @watcher.update!(forum_watch_email_mode: "digest_only")
    @topic = Community::Topic.create!(
      title: "Watch Topic",
      section: @section,
      user: @author,
      status: :published
    )
    Community::Subscription.create!(
      user: @watcher,
      subscribable: @topic,
      notification_level: "watching"
    )
    NotificationPreference.set!(@watcher, channel: "email", notification_type: "forum.topic_reply", enabled: true)
  end

  test "digest_only mode skips instant topic reply email" do
    post_record = Community::Post.create!(
      topic: @topic,
      user: @author,
      body: "reply",
      floor_number: 1,
      status: :published
    )

    assert_no_enqueued_jobs(only: MailDeliveryJob) do
      Community::NotifyTopicReply.call(post: post_record)
    end
  end

  test "instant mode allows topic reply email" do
    @watcher.update!(forum_watch_email_mode: "instant")
    post_record = Community::Post.create!(
      topic: @topic,
      user: @author,
      body: "reply2",
      floor_number: 2,
      status: :published
    )

    assert_enqueued_jobs 1, only: MailDeliveryJob do
      Community::NotifyTopicReply.call(post: post_record)
    end
  end
end

class Round84WatchEmailPreferencesTest < ActionDispatch::IntegrationTest
  setup do
    @watcher = create_user
    @watcher.update!(forum_watch_email_mode: "digest_only")
  end

  test "preferences page includes watch email mode" do
    sign_in_as(@watcher)
    get forum_preferences_path
    assert_response :success
    assert_includes response.body, "watch_email_mode"
    assert_includes response.body, "digest_only"
  end
end

class Round84WebhookDateFilterTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "system.settings.manage")
    @user = create_user
    @search = @user.forum_saved_searches.create!(name: "Date", query: "x", filters: {})
    @old = Community::SavedSearchWebhookDelivery.create!(
      saved_search: @search,
      event_type: "saved_search.match",
      url: "https://example.com/h",
      status: "failed",
      response_code: 500,
      created_at: 3.days.ago
    )
    @recent = Community::SavedSearchWebhookDelivery.create!(
      saved_search: @search,
      event_type: "saved_search.match",
      url: "https://example.com/h",
      status: "failed",
      response_code: 500
    )
  end

  test "forum webhook index filters by date range" do
    sign_in_as(@admin)
    get admin_forum_webhook_deliveries_path,
        params: { status: "failed", created_from: 1.day.ago.to_date.to_s }
    assert_response :success
    assert_includes response.body, "dateFilter"
    assert_includes response.body, @recent.id.to_s
    assert_not_includes response.body, "\"id\":#{@old.id}"
  end

  test "store webhook index filters by date range" do
    old = Commerce::OrderWebhookDelivery.create!(
      event_type: "order.paid",
      order_public_id: "old",
      url: "https://example.com/h",
      status: "failed",
      created_at: 5.days.ago
    )
    recent = Commerce::OrderWebhookDelivery.create!(
      event_type: "order.paid",
      order_public_id: "recent",
      url: "https://example.com/h",
      status: "failed"
    )

    sign_in_as(@admin)
    get admin_store_webhook_deliveries_path,
        params: { status: "failed", created_from: 1.day.ago.to_date.to_s }
    assert_response :success
    assert_includes response.body, recent.order_public_id
    assert_not_includes response.body, old.order_public_id
  end

  test "dashboard includes webhook failed links" do
    sign_in_as(@admin)
    get admin_root_path
    assert_response :success
    assert_includes response.body, "webhookFailedLinks"
    assert_includes response.body, "created_from"
    assert_includes response.body, "status=failed"
  end
end

class Round84WatchingOpmlTopicsTest < ActionDispatch::IntegrationTest
  test "watching opml includes subscribed topics" do
    user = create_user
    section = Community::Section.first || Community::Section.create!(
      name: "OPML Sec",
      slug: "opml-sec-#{SecureRandom.hex(4)}",
      category: Community::Category.find_or_create_by!(slug: "opml-cat") { |c| c.name = "OPML Cat" },
      position: 0
    )
    topic = Community::Topic.create!(
      title: "OPML Topic Title",
      section: section,
      user: user,
      status: :published
    )
    Community::Subscription.create!(user: user, subscribable: topic, notification_level: "watching")

    token = Community::WatchingOpmlToken.generate(user)
    get forum_watching_opml_path(token: token, format: :xml)
    assert_response :success
    assert_includes response.body, "OPML Topic Title"
  end
end
