# frozen_string_literal: true

require "test_helper"

class Community::SyncTopicTagsCreateTopicTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r16-cat") { |c| c.name = "R16" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r16-sec") do |s|
      s.name = "R16 Sec"
      s.position = 0
    end
    @staff_tag = Community::Tag.create!(name: "staff-r16", slug: "staff-r16-#{SecureRandom.hex(3)}", staff_only: true)
  end

  test "create topic fails when staff-only tag rejected" do
    title = "Tagged #{SecureRandom.hex(4)}"
    result = Community::CreateTopic.call(
      user: @user,
      section: @section,
      title: title,
      body: "Body content here",
      tag_names: [ @staff_tag.name ],
      ip_address: "127.0.0.1"
    )

    assert result.failure?
    assert_not Community::Topic.exists?(title: title)
  end
end

class Community::ToggleTagSubscriptionTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @tag = Community::Tag.create!(name: "watch-#{SecureRandom.hex(3)}", slug: "watch-#{SecureRandom.hex(4)}")
  end

  test "toggles tag subscription" do
    result = Community::ToggleTagSubscription.call(user: @user, tag: @tag)
    assert result.success?
    assert result.value[:watching]
    assert_equal "watching", result.value[:notification_level]

    result2 = Community::ToggleTagSubscription.call(user: @user, tag: @tag)
    assert result2.success?
    assert result2.value[:watching]
    assert_equal "tracking", result2.value[:notification_level]

    result3 = Community::ToggleTagSubscription.call(user: @user, tag: @tag)
    assert result3.success?
    assert result3.value[:watching]
    assert_equal "normal", result3.value[:notification_level]

    result4 = Community::ToggleTagSubscription.call(user: @user, tag: @tag)
    assert result4.success?
    assert_not result4.value[:watching]
  end
end

class Community::NotifyPostReactionTest < ActiveSupport::TestCase
  setup do
    @author = create_user
    @reactor = create_user
    category = Community::Category.find_or_create_by!(slug: "react-cat") { |c| c.name = "React" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "react-sec") do |s|
      s.name = "React Sec"
      s.position = 0
    end
    @topic = Community::Topic.create!(
      public_id: "topic_#{SecureRandom.alphanumeric(16)}",
      section: @section,
      user: @author,
      title: "React topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: @author,
      replies_count: 0
    )
    @post = Community::Post.create!(
      topic: @topic,
      user: @author,
      floor_number: 1,
      body: "Hello",
      status: "published"
    )
  end

  test "notifies post author on reaction" do
    assert_difference -> { Notification.where(notification_type: "forum.reaction").count }, 1 do
      Community::NotifyPostReaction.call(post: @post, reactor: @reactor, emoji: "👍")
    end
  end
end

class Community::TrustLevelPmTest < ActiveSupport::TestCase
  test "new user cannot send pm" do
    sender = create_user
    recipient = create_user
    result = Community::CreateConversation.call(
      sender: sender,
      recipient_username: recipient.username,
      body: "hi there"
    )
    assert result.failure?
    assert_match(/private message/i, result.error.to_s)
  end
end

class Community::CreateGroupConversationSelfTest < ActiveSupport::TestCase
  test "removes sender from recipient list" do
    sender = create_user
    enable_forum_pm!(sender)
    alice = create_user(username: "alice_#{SecureRandom.hex(3)}")

    result = Community::CreateGroupConversation.call(
      sender: sender,
      title: "Team",
      recipient_usernames: [ sender.username, alice.username ],
      body: "Hello team"
    )

    assert result.success?
    assert_equal 2, result.value[:conversation].users.count
  end
end

class Commerce::ShowProductQuestionTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_uh_#{SecureRandom.hex(4)}",
      name: "Unhide Product",
      slug: "unhide-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 5
    )
    @question = Commerce::CreateProductQuestion.call(user: @user, product: @product, body: "Q?").value
    Commerce::HideProductQuestion.call(question: @question)
  end

  test "unhides product question" do
    result = Commerce::ShowProductQuestion.call(question: @question)
    assert result.success?
    assert @question.reload.published?
  end
end

class Commerce::ReorderFromOrderTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_ro_#{SecureRandom.hex(4)}",
      name: "Reorder Product",
      slug: "reorder-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 500,
      currency: "CNY",
      stock: 10
    )
    @order = Commerce::Order.create!(
      user: @user,
      order_number: "ORD-RO-#{SecureRandom.hex(4)}",
      status: "paid",
      subtotal_cents: 500,
      discount_cents: 0,
      total_cents: 500,
      currency: "CNY"
    )
    Commerce::OrderItem.create!(
      order: @order,
      product: @product,
      product_name: @product.name,
      quantity: 2,
      unit_price_cents: 500,
      total_cents: 1000
    )
  end

  test "reorders items into cart" do
    result = Commerce::ReorderFromOrder.call(user: @user, order: @order)
    assert result.success?
    assert_equal 1, result.value[:added]
    cart = Commerce::Cart.find_by(user: @user)
    assert cart.items.exists?(store_product_id: @product.id)
  end
end

class Commerce::AddWishlistToCartTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_wl_#{SecureRandom.hex(4)}",
      name: "Wishlist Product",
      slug: "wl-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 5
    )
    Commerce::WishlistItem.create!(user: @user, product: @product)
  end

  test "adds wishlist items to cart" do
    result = Commerce::AddWishlistToCart.call(user: @user)
    assert result.success?
    assert_equal 1, result.value[:added]
  end
end

class Payments::StripeProviderSignatureTest < ActiveSupport::TestCase
  setup do
    config = Payments::ProviderConfig.find_or_create_by!(provider: "stripe") do |c|
      c.enabled = true
    end
    config.update!(credentials: { webhook_secret: "whsec_test_secret" })
    @provider = Payments::StripeProvider.new
  end

  test "rejects invalid stripe signature" do
    payload = '{"id":"evt_test"}'
    refute @provider.verify_webhook_signature(
      payload: payload,
      signature: "t=123,v1=deadbeef",
      headers: { "HTTP_STRIPE_SIGNATURE" => "t=123,v1=deadbeef" }
    )
  end

  test "accepts valid stripe signature" do
    secret = "whsec_test_secret"
    timestamp = Time.now.to_i.to_s
    payload = '{"id":"evt_test"}'
    signed_payload = "#{timestamp}.#{payload}"
    signature = OpenSSL::HMAC.hexdigest("SHA256", secret, signed_payload)
    header = "t=#{timestamp},v1=#{signature}"

    assert @provider.verify_webhook_signature(
      payload: payload,
      signature: header,
      headers: { "HTTP_STRIPE_SIGNATURE" => header }
    )
  end
end
