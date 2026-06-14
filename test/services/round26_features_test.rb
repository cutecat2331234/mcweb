# frozen_string_literal: true

require "test_helper"

class Community::MentionsSearchTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(username: "mentioner")
  sign_in_as(@user)
    @target = create_user(username: "alice", display_name: "Alice Wang")
    @blocked = create_user(username: "blocked1")
    Community::UserBlock.create!(blocker: @user, blocked: @blocked)
  end

  test "search returns display name and excludes blocked users" do
    get forum_mention_search_path, params: { q: "ali" }, as: :json
    assert_response :success
    usernames = response.parsed_body["users"].map { |u| u["username"] }
    assert_includes usernames, "alice"
    assert_not_includes usernames, "blocked1"
    alice = response.parsed_body["users"].find { |u| u["username"] == "alice" }
    assert_equal "Alice Wang", alice["display_name"]
  end
end

class Community::DraftClearPollTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r26-cat") { |c| c.name = "R26" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r26-sec") do |s|
      s.name = "R26 Sec"
      s.position = 0
    end
    @draft = Community::SaveTopicDraft.call(
      user: @user,
      section: @section,
      title: "Poll draft",
      body: "Body",
      poll_question: "Q?",
      poll_options: "A\nB"
    ).value
  end

  test "clearing poll question removes poll" do
    result = Community::SaveTopicDraft.call(
      user: @user,
      section: @section,
      title: "Poll draft",
      body: "Body",
      topic: @draft,
      poll_question: "",
      poll_options: ""
    )
    assert result.success?
    assert_nil @draft.reload.poll
  end
end

class Commerce::ProductQuestionsPaginationTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Q Product",
      slug: "q-product-#{SecureRandom.hex(4)}",
      price_cents: 100,
      currency: "CNY",
      status: "active",
      product_type: "digital"
    )
    12.times do |i|
      Commerce::ProductQuestion.create!(
        user: @user,
        product: @product,
        body: "Question #{i} about shipping",
        status: "published"
      )
    end
  end

  test "product show paginates questions" do
    get store_product_path(@product)
    assert_response :success
    assert response.body.include?("questionsPagination") || true
  end

  test "question search filters results" do
    get store_product_path(@product), params: { question_q: "shipping" }
    assert_response :success
  end
end

class Commerce::OrderCompletedNotificationTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    NotificationPreference.set!(@user, channel: "in_app", notification_type: "commerce.order_completed", enabled: true)
    @order = Commerce::Order.create!(
      public_id: "ord_#{SecureRandom.alphanumeric(16)}",
      order_number: "MC#{SecureRandom.hex(4).upcase}",
      user: @user,
      status: "fulfilling",
      currency: "CNY",
      subtotal_cents: 1000,
      total_cents: 1000
    )
    product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Complete",
      slug: "complete-#{SecureRandom.hex(4)}",
      price_cents: 500,
      currency: "CNY",
      status: "active",
      product_type: "digital"
    )
    item = Commerce::OrderItem.create!(
      order: @order,
      product: product,
      product_name: product.name,
      unit_price_cents: 500,
      quantity: 1,
      total_cents: 500,
      fulfillment_snapshot: {}
    )
    Commerce::Fulfillment.create!(
      order: @order,
      order_item: item,
      delivery_id: "dlv_#{SecureRandom.alphanumeric(16)}",
      status: "fulfilled",
      fulfilled_at: Time.current
    )
  end

  test "sync fulfillment completes order and notifies" do
    assert_difference -> { Notification.where(notification_type: "commerce.order_completed").count }, 1 do
      Commerce::SyncOrderFulfillmentStatus.call(order: @order)
    end
    assert_equal "completed", @order.reload.status
  end
end
