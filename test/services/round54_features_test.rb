# frozen_string_literal: true

require "test_helper"

class Community::ParseSearchQueryRound54Test < ActiveSupport::TestCase
  test "parses is:mine and in:bookmarks" do
    result = Community::ParseSearchQuery.call(query: "is:mine bugs in:bookmarks")
    assert result.success?
    assert_equal "mine", result.value[:mine_filter]
    assert_equal "bookmarks", result.value[:scope_filter]
    assert_equal "bugs", result.value[:query]
  end
end

class Community::FindSimilarTitlesTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    suffix = SecureRandom.hex(4)
    category = Community::Category.find_or_create_by!(slug: "r54-sim-#{suffix}") { |c| c.name = "S" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r54-sim-sec-#{suffix}") { |s| s.name = "S"; s.position = 0 }
    Community::CreateTopic.call(user: @user, section: @section, title: "How to install mods", body: "OP", ip_address: "127.0.0.1")
  end

  test "finds similar titles in section" do
    result = Community::FindSimilarTitles.call(section: @section, title: "install mod")
    assert result.success?
    assert_equal 1, result.value[:titles].size
    assert_includes result.value[:titles].first[:title], "install"
  end
end

class Community::ChangePostAuthorTest < ActiveSupport::TestCase
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    @author = create_user
    @new_author = create_user
    category = Community::Category.find_or_create_by!(slug: "r54-auth-#{SecureRandom.hex(4)}") { |c| c.name = "A" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r54-auth-sec-#{SecureRandom.hex(4)}") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @author, section: @section, title: "Auth", body: "OP", ip_address: "127.0.0.1").value
    @post = @topic.posts.first
  end

  test "moderator can change post author" do
    result = Community::ChangePostAuthor.call(user: @mod, post: @post, new_username: @new_author.username)
    assert result.success?
    assert_equal @new_author.id, @post.reload.user_id
    assert_equal @new_author.id, @topic.reload.user_id
  end
end

class Community::ToggleReactionEmojiSettingTest < ActiveSupport::TestCase
  setup do
    SiteSetting.set("forum.reaction_emojis", "🔥,👍")
  end

  teardown do
    SiteSetting.set("forum.reaction_emojis", "👍,❤️,😂,🎉,👀")
  end

  test "allowed emoji from site setting" do
    assert_equal %w[🔥 👍], Community::ToggleReaction.allowed_emoji
  end
end

class Community::SearchSuggestTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r54-sug-#{SecureRandom.hex(4)}") { |c| c.name = "S" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r54-sug-sec-#{SecureRandom.hex(4)}") { |s| s.name = "S"; s.position = 0 }
    Community::CreateTopic.call(user: @user, section: @section, title: "Suggestable topic", body: "OP", ip_address: "127.0.0.1")
  end

  test "search suggest returns topics" do
    get forum_search_suggest_path, params: { q: "Suggest" }, as: :json
    assert_response :success
    data = JSON.parse(response.body)
    assert data["topics"].any? { |t| t["title"].include?("Suggestable") }
  end
end

class Commerce::CancelOrderReasonTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_cancel_r54_#{SecureRandom.hex(8)}",
      order_number: "MC#{SecureRandom.hex(4)}",
      user: @user,
      status: "pending",
      subtotal_cents: 1000,
      total_cents: 1000,
      currency: "CNY"
    )
  end

  test "cancel stores reason in order event" do
    result = Commerce::CancelOrder.call(order: @order, actor: @user, reason: "Changed mind")
    assert result.success?
    event = Commerce::OrderEvent.find_by(order: @order, event_type: "cancel")
    assert_equal "Changed mind", event.metadata["reason"]
  end
end

class Commerce::SendReviewRequestTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_rev_r54_#{SecureRandom.hex(4)}",
      name: "Review Me",
      slug: "rev-r54-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY"
    )
    @order = Commerce::Order.create!(
      public_id: "ord_rev_r54_#{SecureRandom.hex(8)}",
      order_number: "MC#{SecureRandom.hex(4)}",
      user: @user,
      status: "completed",
      subtotal_cents: 100,
      total_cents: 100,
      currency: "CNY"
    )
    Commerce::OrderItem.create!(
      order: @order,
      product: @product,
      product_name: @product.name,
      unit_price_cents: 100,
      quantity: 1,
      total_cents: 100,
      fulfillment_snapshot: { product_type: "virtual" }
    )
  end

  test "sends review request once" do
    assert_difference -> { Notification.where(user: @user, notification_type: "commerce.review_request").count }, 1 do
      Commerce::SendReviewRequest.call(order: @order)
    end
    assert @order.reload.review_request_sent_at.present?
    result = Commerce::SendReviewRequest.call(order: @order)
    assert result.value[:skipped]
  end
end

class Commerce::SkuSearchTest < ActionDispatch::IntegrationTest
  setup do
    @product = Commerce::Product.create!(
      public_id: "prod_sku_r54_#{SecureRandom.hex(4)}",
      name: "SKU Product",
      slug: "sku-r54-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY"
    )
    Commerce::ProductVariant.create!(
      product: @product,
      name: "Default",
      sku: "UNIQUE-SKU-R54-XYZ",
      price_cents: 100,
      stock: 10
    )
  end

  test "store index finds product by variant sku" do
    get store_products_path, params: { q: "UNIQUE-SKU-R54" }
    assert_response :success
    assert_includes response.body, @product.name
  end
end

class Commerce::WebhookDeliveryLogTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_wh_r54_#{SecureRandom.hex(8)}",
      order_number: "MC#{SecureRandom.hex(4)}",
      user: @user,
      status: "paid",
      subtotal_cents: 1000,
      total_cents: 1000,
      currency: "CNY"
    )
  end

  test "delivery record can be created" do
    delivery = Commerce::OrderWebhookDelivery.create!(
      event_type: "order.test",
      order_public_id: @order.public_id,
      url: "https://example.com/hook",
      status: "success",
      response_code: 200,
      response_body: "ok"
    )
    assert delivery.persisted?
  end
end
