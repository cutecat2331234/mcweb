# frozen_string_literal: true

require "test_helper"

class Round82ForumWebhookHmacTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @previous = SiteSetting.get("forum.saved_search_webhook_secret")
    SiteSetting.set("forum.saved_search_webhook_secret", "forum-whsec-r82")
    @user = create_user
    @search = @user.forum_saved_searches.create!(
      name: "HMAC Hook",
      query: "x",
      webhook_url: "https://example.com/hook",
      filters: {}
    )
  end

  teardown do
    SiteSetting.set("forum.saved_search_webhook_secret", @previous || "")
  end

  test "webhook signature helper produces sha256 header" do
    body = '{"event":"test"}'
    header = WebhookSignature.header_for("secret", body)
    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', 'secret', body)}"
    assert_equal expected, header
  end

  test "dispatch saved search webhook enqueues job when url present" do
    assert_enqueued_with(job: Community::DispatchSavedSearchWebhookJob) do
      Community::DispatchSavedSearchWebhook.call(
        saved_search: @search,
        topics: []
      )
    end
  end

  test "dispatch service passes webhook secret" do
    content = File.read(Rails.root.join("app/services/community/dispatch_saved_search_webhook.rb"))
    assert_includes content, "forum.saved_search_webhook_secret"
    assert_includes content, "secret: secret"
  end

  test "forum settings include webhook secret" do
    content = File.read(Rails.root.join("app/controllers/admin/forum/settings_controller.rb"))
    assert_includes content, "forum.saved_search_webhook_secret"
  end
end

class Round82PostsOnlySearchTest < ActionDispatch::IntegrationTest
  setup do
    @section = Community::Section.first || Community::Section.create!(
      name: "R82 Section",
      slug: "r82-sec-#{SecureRandom.hex(4)}",
      category: Community::Category.find_or_create_by!(slug: "r82-cat") { |c| c.name = "R82 Cat" },
      position: 0
    )
    @user = create_user
    @topic = Community::Topic.create!(
      title: "R82TitleOnly",
      section: @section,
      user: @user,
      status: :published
    )
    Community::Post.create!(
      topic: @topic,
      user: @user,
      body: "R82BodyUniqueKeyword in post",
      floor_number: 1,
      status: :published
    )
  end

  test "posts only search returns posts not topics" do
    get forum_search_path, params: { q: "R82BodyUniqueKeyword", posts_only: "1" }
    assert_response :success
    assert_includes response.body, "R82BodyUniqueKeyword"
    assert_includes response.body, '"topics":[]'
  end

  test "parse search query supports in:posts" do
    result = Community::ParseSearchQuery.call(query: "hello in:posts")
    assert result.success?
    assert_equal "hello", result.value[:query]
    assert result.value[:posts_only_filter]
  end

  test "search page supports posts only and share link" do
    content = File.read(Rails.root.join("app/javascript/pages/Community/Search/Index.vue"))
    assert_includes content, "postsOnly"
    assert_includes content, "仅帖子"
    assert_includes content, "copySearchLink"
  end
end

class Round82StoreWebhookShowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "system.settings.manage")
    @delivery = Commerce::OrderWebhookDelivery.create!(
      event_type: "order.paid",
      order_public_id: "ord_r82",
      url: "https://example.com/hook",
      status: "failed",
      response_code: 500,
      response_body: "err",
      request_payload: { "event" => "order.paid", "order_id" => "ord_r82" },
      attempt_count: 2
    )
  end

  test "admin store webhook delivery show" do
    sign_in_as(@admin)
    get admin_store_webhook_delivery_path(@delivery)
    assert_response :success
    assert_includes response.body, "preformattedSections"
    assert_includes response.body, "ord_r82"
  end

  test "admin store webhook index has event tabs" do
    sign_in_as(@admin)
    get admin_store_webhook_deliveries_path
    assert_response :success
    assert_includes response.body, "eventTabs"
    assert_includes response.body, "order.paid"
  end

  test "admin store webhook retry" do
    sign_in_as(@admin)
    assert_enqueued_with(job: Commerce::DispatchOrderWebhookJob) do
      post retry_admin_store_webhook_delivery_path(@delivery)
    end
    assert_redirected_to admin_store_webhook_delivery_path(@delivery)
  end
end

class Round82ForumWebhookEventFilterTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "system.settings.manage")
    @user = create_user
    @search = @user.forum_saved_searches.create!(name: "Evt", query: "x", filters: {})
    Community::SavedSearchWebhookDelivery.create!(
      saved_search: @search,
      event_type: "saved_search.match",
      url: "https://example.com/h",
      status: "success",
      response_code: 200
    )
  end

  test "forum webhook index filters by event" do
    sign_in_as(@admin)
    get admin_forum_webhook_deliveries_path, params: { event: "saved_search.match" }
    assert_response :success
    assert_includes response.body, "eventTabs"
    assert_includes response.body, "Evt"
  end
end

class Round82WebhookSignatureRefactorTest < ActiveSupport::TestCase
  test "order webhook job uses signature helper" do
    content = File.read(Rails.root.join("app/jobs/commerce/dispatch_order_webhook_job.rb"))
    assert_includes content, "WebhookSignature.header_for"
  end

  test "forum webhook job uses signature helper" do
    content = File.read(Rails.root.join("app/jobs/community/dispatch_saved_search_webhook_job.rb"))
    assert_includes content, "WebhookSignature.header_for"
  end
end
