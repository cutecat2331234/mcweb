# frozen_string_literal: true

require "test_helper"

class Round83SearchRssTokenTest < ActiveSupport::TestCase
  test "generate and verify roundtrip" do
    params = { "q" => "hello", "section" => "general", "title_only" => "1" }
    token = Community::SearchRssToken.generate(params)
    verified = Community::SearchRssToken.verify(token)
    assert_equal Community::SearchRssToken.normalize(params), verified
  end

  test "verify rejects invalid token" do
    assert_raises(Community::SearchRssToken::InvalidToken) do
      Community::SearchRssToken.verify("bad-token")
    end
  end

  test "normalize strips blank values" do
    normalized = Community::SearchRssToken.normalize({ q: "x", section: "", tag: nil })
    assert_equal({ "q" => "x" }, normalized)
  end
end

class Round83AdHocSearchRssTest < ActionDispatch::IntegrationTest
  setup do
    @section = Community::Section.first || Community::Section.create!(
      name: "R83 Section",
      slug: "r83-sec-#{SecureRandom.hex(4)}",
      category: Community::Category.find_or_create_by!(slug: "r83-cat") { |c| c.name = "R83 Cat" },
      position: 0
    )
    @user = create_user
    @keyword = "R83RssUnique#{SecureRandom.hex(4)}"
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

  test "ad hoc search rss returns matching topics" do
    rss_params = { q: @keyword }
    token = Community::SearchRssToken.generate(rss_params)
    get forum_search_rss_path(rss_params.merge(token: token, format: :rss))
    assert_response :success
    assert_includes response.body, @keyword
    assert_includes response.body, "<rss"
  end

  test "ad hoc search rss rejects tampered params" do
    rss_params = { q: @keyword }
    token = Community::SearchRssToken.generate(rss_params)
    get forum_search_rss_path(rss_params.merge(token: token, q: "other", format: :rss))
    assert_response :not_found
  end

  test "search page exposes search rss url" do
    get forum_search_path, params: { q: @keyword }
    assert_response :success
    assert_includes response.body, "searchRssUrl"
    assert_includes response.body, "search.rss"
  end
end

class Round83SearchHighlightTest < ActionDispatch::IntegrationTest
  setup do
    @section = Community::Section.first || Community::Section.create!(
      name: "R83 HL Section",
      slug: "r83-hl-#{SecureRandom.hex(4)}",
      category: Community::Category.find_or_create_by!(slug: "r83-hl-cat") { |c| c.name = "R83 HL Cat" },
      position: 0
    )
    @user = create_user
    @keyword = "R83Highlight#{SecureRandom.hex(4)}"
    @topic = Community::Topic.create!(
      title: "Prefix #{@keyword} Suffix",
      section: @section,
      user: @user,
      status: :published
    )
    Community::Post.create!(
      topic: @topic,
      user: @user,
      body: "Post body contains #{@keyword} here",
      floor_number: 1,
      status: :published
    )
  end

  test "search highlights topic titles" do
    get forum_search_path, params: { q: @keyword }
    assert_response :success
    assert_includes response.body, "title_html"
    assert_match(/\\u003cmark\\u003e#{Regexp.escape(@keyword)}\\u003c\/mark\\u003e/, response.body)
  end

  test "search post results use body_html" do
    get forum_search_path, params: { q: @keyword }
    assert_response :success
    assert_includes response.body, "body_html"
    assert_match(/\\u003cmark\\u003e#{Regexp.escape(@keyword)}\\u003c\/mark\\u003e/, response.body)
  end
end

class Round83WebhookDeliveryStatsTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @search = @user.forum_saved_searches.create!(name: "Stats", query: "x", filters: {})
  end

  test "summary counts forum and store deliveries in 24h window" do
    Community::SavedSearchWebhookDelivery.create!(
      saved_search: @search,
      event_type: "saved_search.match",
      url: "https://example.com/h",
      status: "success",
      response_code: 200
    )
    Community::SavedSearchWebhookDelivery.create!(
      saved_search: @search,
      event_type: "saved_search.match",
      url: "https://example.com/h",
      status: "failed",
      response_code: 500
    )
    Commerce::OrderWebhookDelivery.create!(
      event_type: "order.paid",
      order_public_id: "ord_r83",
      url: "https://example.com/hook",
      status: "pending"
    )

    stats = WebhookDeliveryStats.summary
    assert_equal 2, stats[:forum][:total]
    assert_equal 1, stats[:forum][:success]
    assert_equal 1, stats[:forum][:failed]
    assert_equal 50.0, stats[:forum][:success_rate]
    assert_equal 1, stats[:store][:total]
    assert_equal 1, stats[:store][:pending]
  end
end

class Round83BulkRetryWebhooksTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = create_user
    @search = @user.forum_saved_searches.create!(
      name: "Bulk",
      query: "x",
      webhook_url: "https://example.com/hook",
      filters: {}
    )
    @forum_delivery = Community::SavedSearchWebhookDelivery.create!(
      saved_search: @search,
      event_type: "saved_search.match",
      url: "https://example.com/hook",
      status: "failed",
      request_payload: { "event" => "saved_search.match" },
      attempt_count: 2
    )
    @store_delivery = Commerce::OrderWebhookDelivery.create!(
      event_type: "order.paid",
      order_public_id: "ord_bulk",
      url: "https://example.com/hook",
      status: "failed",
      request_payload: { "event" => "order.paid" },
      attempt_count: 2
    )
  end

  test "bulk retry forum failed deliveries" do
    assert_enqueued_jobs 1, only: Community::DispatchSavedSearchWebhookJob do
      result = Community::BulkRetrySavedSearchWebhooks.call(delivery_ids: [ @forum_delivery.id ])
      assert result.success?
      assert_equal 1, result.value[:queued]
    end
  end

  test "bulk retry store failed deliveries" do
    assert_enqueued_jobs 1, only: Commerce::DispatchOrderWebhookJob do
      result = Commerce::BulkRetryOrderWebhooks.call(delivery_ids: [ @store_delivery.id ])
      assert result.success?
      assert_equal 1, result.value[:queued]
    end
  end

  test "bulk retry rejects empty ids" do
    result = Community::BulkRetrySavedSearchWebhooks.call(delivery_ids: [])
    assert result.failure?
    assert_includes result.error, "未选择"
  end
end

class Round83AdminWebhookBulkRetryTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "system.settings.manage")
    @user = create_user
    @search = @user.forum_saved_searches.create!(
      name: "Bulk Admin",
      query: "x",
      webhook_url: "https://example.com/hook",
      filters: {}
    )
    @forum_delivery = Community::SavedSearchWebhookDelivery.create!(
      saved_search: @search,
      event_type: "saved_search.match",
      url: "https://example.com/hook",
      status: "failed",
      request_payload: { "event" => "saved_search.match" },
      attempt_count: 2
    )
    @store_delivery = Commerce::OrderWebhookDelivery.create!(
      event_type: "order.paid",
      order_public_id: "ord_r83_admin",
      url: "https://example.com/hook",
      status: "failed",
      request_payload: { "event" => "order.paid" },
      attempt_count: 2
    )
  end

  test "admin dashboard includes webhook stats" do
    sign_in_as(@admin)
    get admin_root_path
    assert_response :success
    assert_includes response.body, "webhookStats"
    assert_includes response.body, "success_rate"
  end

  test "forum webhook index includes bulk retry props" do
    sign_in_as(@admin)
    get admin_forum_webhook_deliveries_path, params: { status: "failed" }
    assert_response :success
    assert_includes response.body, "bulkRetry"
    assert_includes response.body, @forum_delivery.id.to_s
  end

  test "forum bulk retry endpoint queues jobs" do
    sign_in_as(@admin)
    assert_enqueued_jobs 1, only: Community::DispatchSavedSearchWebhookJob do
      post bulk_retry_admin_forum_webhook_deliveries_path, params: { ids: [ @forum_delivery.id ] }
    end
    assert_redirected_to admin_forum_webhook_deliveries_path
  end

  test "store bulk retry endpoint queues jobs" do
    sign_in_as(@admin)
    assert_enqueued_jobs 1, only: Commerce::DispatchOrderWebhookJob do
      post bulk_retry_admin_store_webhook_deliveries_path, params: { ids: [ @store_delivery.id ] }
    end
    assert_redirected_to admin_store_webhook_deliveries_path
  end
end
