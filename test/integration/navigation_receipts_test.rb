# frozen_string_literal: true

require "test_helper"

class NavigationReceiptTest < ActiveSupport::TestCase
  setup do
    NavigationReceipt.cache_store = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    NavigationReceipt.cache_store = nil
  end

  test "a signed receipt runs its effect only once and is bound to its subject" do
    token = NavigationReceipt.issue(
      kind: "example.page",
      resource_id: "page_1",
      user_id: 42,
      attributes: { through: 7 }
    )
    effects = 0

    first = NavigationReceipt.consume(
      token: token,
      kind: "example.page",
      resource_id: "page_1",
      user_id: 42
    ) { |attributes| effects += attributes.fetch(:through) }
    second = NavigationReceipt.consume(
      token: token,
      kind: "example.page",
      resource_id: "page_1",
      user_id: 42
    ) { effects += 100 }
    wrong_user = NavigationReceipt.consume(
      token: token,
      kind: "example.page",
      resource_id: "page_1",
      user_id: 43
    )

    assert first.success?
    assert_equal true, first.value[:fresh]
    assert second.success?
    assert_equal false, second.value[:fresh]
    assert wrong_user.failure?
    assert_equal 7, effects
  end

  test "a failed effect releases the receipt for a safe retry" do
    token = NavigationReceipt.issue(
      kind: "example.page",
      resource_id: "page_2",
      user_id: nil
    )

    assert_raises RuntimeError do
      NavigationReceipt.consume(
        token: token,
        kind: "example.page",
        resource_id: "page_2",
        user_id: nil
      ) { raise "effect failed" }
    end

    retried = false
    result = NavigationReceipt.consume(
      token: token,
      kind: "example.page",
      resource_id: "page_2",
      user_id: nil
    ) { retried = true }

    assert result.success?
    assert retried
  end
end

class NavigationReceiptIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    NavigationReceipt.cache_store = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    NavigationReceipt.cache_store = nil
  end

  test "topic GET is pure and the mounted-page receipt records the visible floor once" do
    reader = create_user
    author = create_user
    category = Community::Category.create!(
      name: "Receipt category",
      slug: "receipt-category-#{SecureRandom.hex(4)}"
    )
    section = Community::Section.create!(
      category: category,
      name: "Receipt section",
      slug: "receipt-section-#{SecureRandom.hex(4)}",
      position: 0
    )
    topic = Community::CreateTopic.call(
      user: author,
      section: section,
      title: "Pure topic visit",
      body: "Opening post",
      ip_address: "127.0.0.1"
    ).value
    notification = reader.notifications.create!(
      notification_type: "forum.mention",
      title: "Topic mention",
      metadata: { "topic_id" => topic.public_id, "path" => forum_topic_path(topic) }
    )
    initial_views = topic.views_count
    sign_in_as(reader)

    get forum_topic_path(topic), headers: inertia_headers(
      application: "forum",
      referer: "/app/forum/latest"
    )

    assert_response :success
    assert_equal initial_views, topic.reload.views_count
    assert_nil Community::ReadState.find_by(user: reader, topic: topic)
    assert_nil notification.reload.read_at
    receipt = inertia_props.fetch("visitReceipt")

    post receipt.fetch("url"), params: { receipt_token: receipt.fetch("token") }, as: :json

    assert_response :no_content
    assert_equal initial_views + 1, topic.reload.views_count
    assert_equal 1, Community::ReadState.find_by!(user: reader, topic: topic).last_read_floor
    assert notification.reload.read?

    post receipt.fetch("url"), params: { receipt_token: receipt.fetch("token") }, as: :json
    assert_response :no_content
    assert_equal initial_views + 1, topic.reload.views_count
  end

  test "conversation GET is pure and its receipt does not mark a later message read" do
    sender = create_user
    recipient = create_user
    enable_forum_pm!(sender)
    enable_forum_pm!(recipient)
    result = Community::CreateConversation.call(
      sender: sender,
      recipient_username: recipient.username,
      body: "First message",
      ip_address: "127.0.0.1"
    )
    conversation = result.value.fetch(:conversation)
    participant = conversation.participants.find_by!(user: recipient)
    sign_in_as(recipient)

    get forum_conversation_path(conversation), headers: inertia_headers(
      application: "forum",
      referer: "/app/forum/latest"
    )

    assert_response :success
    assert_nil participant.reload.last_read_at
    receipt = inertia_props.fetch("readReceipt")
    later_message = conversation.messages.create!(user: sender, body: "Arrived after render")

    post receipt.fetch("url"), params: { receipt_token: receipt.fetch("token") }, as: :json

    assert_response :no_content
    assert_operator participant.reload.last_read_at, :<, later_message.created_at
    assert_equal 1, conversation.unread_count_for(recipient)
  end

  test "product GET is pure and its mounted-page receipt records one view" do
    user = create_user
    product = Commerce::Product.create!(
      name: "Receipt product",
      slug: "receipt-product-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: :active,
      price_cents: 100,
      currency: "CNY",
      minimum_quantity: 1,
      stock: 5,
      public_id: "pub_receipt_#{SecureRandom.hex(6)}"
    )
    sign_in_as(user)

    get store_product_path(product), headers: inertia_headers(
      application: "store",
      referer: "/app/store/products"
    )

    assert_response :success
    assert_equal 0, product.reload.view_count
    assert_not Commerce::ProductView.exists?(user: user, product: product)
    receipt = inertia_props.fetch("viewReceipt")

    post receipt.fetch("url"), params: { receipt_token: receipt.fetch("token") }, as: :json

    assert_response :no_content
    assert_equal 1, product.reload.view_count
    assert Commerce::ProductView.exists?(user: user, product: product)

    post receipt.fetch("url"), params: { receipt_token: receipt.fetch("token") }, as: :json
    assert_response :no_content
    assert_equal 1, product.reload.view_count
  end

  test "notifications GET stays unread until the mounted page dismisses transient alerts" do
    user = create_user
    notification = user.notifications.create!(
      notification_type: "forum.reaction",
      title: "Transient reaction",
      auto_dismiss: true
    )
    sign_in_as(user)

    get account_notifications_path, headers: inertia_headers(
      application: "account",
      referer: "/app/account"
    )

    assert_response :success
    assert_nil notification.reload.read_at
    dismiss_url = inertia_props.fetch("dismissAlertsUrl")

    patch dismiss_url, headers: {
      "X-Requested-With" => "XMLHttpRequest",
      "Accept" => "application/json"
    }

    assert_response :no_content
    assert notification.reload.read?
  end

  private

  def inertia_headers(application:, referer:)
    {
      "X-Inertia" => "true",
      "X-Inertia-Version" => InertiaRails.configuration.version,
      "X-McWeb-Application" => application,
      "HTTP_REFERER" => "http://www.example.com#{referer}"
    }
  end

  def inertia_props
    JSON.parse(response.body).fetch("props")
  end
end
