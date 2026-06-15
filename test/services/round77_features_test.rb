# frozen_string_literal: true

require "test_helper"

module Round77TestHelpers
  def self.create_forum_topic(user:, title:)
    category = Community::Category.find_or_create_by!(slug: "r77-cat-#{SecureRandom.hex(4)}") { |c| c.name = "R77 Cat" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r77-sec-#{SecureRandom.hex(4)}") do |s|
      s.name = "R77 Sec"
      s.position = 0
    end
    Community::Topic.create!(
      public_id: "topic_#{SecureRandom.hex(8)}",
      section: section,
      user: user,
      title: title,
      status: :published,
      last_posted_at: Time.current,
      last_post_user: user
    )
  end
end

class Round77SavedSearchFilterSummaryTest < ActiveSupport::TestCase
  test "filter summary includes query and solved filter" do
    user = create_user
    search = user.forum_saved_searches.create!(
      name: "Bug hunt",
      query: "release",
      filters: { solved: "unsolved", author: "alice" }
    )

    labels = Community::SavedSearchFilterSummary.call(search)
    assert_includes labels, "关键词：release"
    assert_includes labels, "作者：alice"
    assert_includes labels, "未解决"
  end

  test "digest email template shows filter chips" do
    content = File.read(Rails.root.join("app/views/community/forum_mailer/saved_search_digest.html.erb"))
    assert_includes content, "@filter_labels"
    assert_includes content, "筛选条件"
  end

  test "digest mailer sets filter labels and rss url" do
    user = create_user
    topic = Round77TestHelpers.create_forum_topic(user: user, title: "Digest topic")
    search = user.forum_saved_searches.create!(name: "Mail", query: "digest", notify_daily: true, filters: { solved: "unsolved" })

    mail = Community::ForumMailer.saved_search_digest(search.id, [ topic.id ])
    body = mail.body.encoded
    assert_includes body, "未解决"
    assert_includes body, "RSS"
  end
end

class Round77SavedSearchRssTest < ActionDispatch::IntegrationTest
  test "saved search rss returns feed with valid token" do
    user = create_user
    Round77TestHelpers.create_forum_topic(user: user, title: "RSS topic")
    search = user.forum_saved_searches.create!(name: "Feed", query: "RSS", filters: {})
    token = Community::SavedSearchRssToken.generate(search)

    get forum_saved_search_rss_path(id: search.id, token: token)
    assert_response :success
    assert_equal "application/rss+xml", response.media_type
    assert_includes response.body, "RSS topic"
    assert_includes response.body, "<rss"
  end

  test "saved search rss rejects invalid token" do
    user = create_user
    search = user.forum_saved_searches.create!(name: "Feed", query: "x", filters: {})

    get forum_saved_search_rss_path(id: search.id, token: "invalid")
    assert_response :not_found
  end

  test "search page exposes rss url for saved searches" do
    user = create_user
    search = user.forum_saved_searches.create!(name: "Sub", query: "q", filters: {})
    sign_in_as(user)

    get forum_search_path
    assert_response :success
    assert_includes response.body, "rss_url"
    assert_includes response.body, forum_saved_search_rss_path(id: search.id, token: Community::SavedSearchRssToken.generate(search))
  end
end

class Round77SavedSearchDigestHourTest < ActiveSupport::TestCase
  setup do
    @previous = SiteSetting.get("forum.saved_search_digest_hour")
    SiteSetting.set("forum.saved_search_digest_hour", (Time.current.hour + 1) % 24)
  end

  teardown do
    SiteSetting.set("forum.saved_search_digest_hour", @previous || "9")
  end

  test "send digests skips when hour does not match setting" do
    user = create_user(email: "digest-hour@example.com")
    user.forum_saved_searches.create!(name: "Hour", query: "x", notify_daily: true, filters: {})

    result = Community::SendSavedSearchDigests.call
    assert result.success?
    assert_equal :wrong_hour, result.value[:reason]
  end
end

class Round77ForumSettingsDigestHourTest < ActionDispatch::IntegrationTest
  test "forum settings includes digest hour" do
    content = File.read(Rails.root.join("app/controllers/admin/forum/settings_controller.rb"))
    assert_includes content, "forum.saved_search_digest_hour"
  end
end

class Round77CheckoutDeliveryEstimateTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      name: "R77 Ship Product",
      slug: "r77-ship-#{SecureRandom.hex(4)}",
      product_type: "physical",
      status: "active",
      price_cents: 1500,
      currency: "CNY",
      requires_shipping: true
    )
    cart = Commerce::Cart.create!(user: @user)
    cart.add_item!(product: @product, quantity: 1)
    sign_in_as(@user)
  end

  test "checkout vue shows selected shipping estimate" do
    content = File.read(Rails.root.join("app/javascript/pages/Commerce/Checkout/Show.vue"))
    assert_includes content, "selectedShippingEstimate"
    assert_includes content, "delivery_estimate"
  end

  test "checkout page exposes delivery estimate in shipping methods" do
    get store_checkout_path
    assert_response :success
    assert_includes response.body, "delivery_estimate"
  end
end

class Round77RecurringDigestScheduleTest < ActiveSupport::TestCase
  test "saved search digest runs hourly" do
    content = File.read(Rails.root.join("config/recurring.yml"))
    assert_includes content, "every hour at minute 5"
  end
end
