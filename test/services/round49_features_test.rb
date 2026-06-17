# frozen_string_literal: true

require "test_helper"


class Administration::BanUserSessionTest < ActiveSupport::TestCase
  setup do
    @admin = create_user
    @target = create_user
    @session_result = Identity::SessionManager.call(
      user: @target,
      ip_address: "127.0.0.1",
      user_agent: "Test"
    )
    @session = @session_result.value[:session]
  end

  test "ban revokes active sessions" do
    result = Administration::BanUser.call(user: @target, actor: @admin, reason: "spam")
    assert result.success?
    assert @session.reload.revoked?
  end
end

class Identity::DeletedUserAuthTest < ActiveSupport::TestCase
  test "rejects login for deleted account" do
    user = create_user(email: "deleted@example.com", username: "deleteduser")
    user.soft_delete!

    result = Identity::AuthenticateUser.call(
      email: "deleted@example.com",
      password: "password123",
      ip_address: "127.0.0.1",
      user_agent: "Test"
    )

    assert result.failure?
    assert_match(/deleted/i, result.error)
  end
end

class Identity::VerifyEmailExpiryTest < ActiveSupport::TestCase
  test "rejects expired verification token" do
    token = SecureRandom.urlsafe_base64(32)
    User.create!(
      email: "expired@example.com",
      username: "expireduser",
      password: "password123",
      password_confirmation: "password123",
      email_verified: false,
      email_verification_token_digest: Digest::SHA256.hexdigest(token),
      email_verification_sent_at: 25.hours.ago
    )

    result = Identity::VerifyEmail.call(token: token)
    assert result.failure?
  end
end

class Payments::StripeProviderMissingSecretTest < ActiveSupport::TestCase
  test "rejects webhook when secret is not configured" do
    Payments::ProviderConfig.where(provider: "stripe").delete_all
    provider = Payments::StripeProvider.new

    refute provider.verify_webhook_signature(
      payload: "{}",
      signature: "t=1,v1=abc",
      headers: { "HTTP_STRIPE_SIGNATURE" => "t=1,v1=abc" }
    )
  end
end

class Payments::FakeProviderProductionSecretTest < ActiveSupport::TestCase
  test "rejects webhook when secret is not configured" do
    provider = Payments::FakeProvider.new
    provider.define_singleton_method(:webhook_secret) { nil }

    refute provider.verify_webhook_signature(payload: "{}", signature: "deadbeef")
  end
end

class UserSoftDeleteSessionTest < ActiveSupport::TestCase
  test "soft delete revokes active sessions" do
    user = create_user
    session_result = Identity::SessionManager.call(
      user: user,
      ip_address: "127.0.0.1",
      user_agent: "Test"
    )
    session = session_result.value[:session]

    user.soft_delete!
    assert session.reload.revoked?
  end
end

class BannedSessionIntegrationTest < ActionDispatch::IntegrationTest
  test "banned user loses access on next request" do
    user = create_user
    sign_in_as(user)

    get forum_notifications_path
    assert_response :success

    user.update!(status: :banned, banned_at: Time.current)

    get forum_notifications_path
    assert_redirected_to identity_sign_in_path
  end
end

class Community::WhisperPostTest < ActiveSupport::TestCase
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.topics.lock")
    @viewer = create_user
    category = Community::Category.find_or_create_by!(slug: "r49-whisper") { |c| c.name = "W" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r49-whisper-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @mod, section: @section, title: "Whisper topic", body: "OP body here", ip_address: "127.0.0.1").value
  end

  test "staff can create whisper post" do
    result = Community::CreatePost.call(user: @mod, topic: @topic, body: "secret", whisper: true, skip_interval_check: true)
    assert result.success?, result.error
    assert result.value.whisper?
  end

  test "regular user cannot create whisper" do
    result = Community::CreatePost.call(user: @viewer, topic: @topic, body: "secret", whisper: true, skip_interval_check: true)
    assert result.failure?
  end
end

class Community::ShareTopicAsConversationTest < ActiveSupport::TestCase
  setup do
    @author = create_user
    @recipient = create_user
    category = Community::Category.find_or_create_by!(slug: "r49-share") { |c| c.name = "S" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r49-share-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @author, section: @section, title: "Share me", body: "OP", ip_address: "127.0.0.1").value
  end

  test "author shares topic via pm" do
    result = Community::ShareTopicAsConversation.call(
      sender: @author,
      topic: @topic,
      recipient_username: @recipient.username
    )
    assert result.success?, result.error
    assert result.value[:conversation].present?
  end
end

class Community::EditTopicPollTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r49-poll") { |c| c.name = "P" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r49-poll-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(
      user: @user, section: @section, title: "Poll topic", body: "OP",
      poll_question: "Color?", poll_options: %w[Red Blue],
      ip_address: "127.0.0.1"
    ).value
    assert @topic.poll.present?, "poll should be created with topic"
  end

  test "author can extend poll close days" do
    result = Community::EditTopicPoll.call(user: @user, topic: @topic, poll_closes_days: 7)
    assert result.success?, result.error
    assert @topic.poll.reload.closes_at.present?
  end
end

class Commerce::ShippingMethodsTest < ActiveSupport::TestCase
  CartItem = Struct.new(:product, keyword_init: true)

  test "lists default shipping methods" do
    methods = Commerce::ShippingMethods.list
    assert methods.size >= 2
    assert methods.any? { |m| m["code"] == "standard" }
  end

  test "calculate shipping uses method code" do
    product = Commerce::Product.create!(
      name: "Shippable", slug: "ship-#{SecureRandom.hex(4)}", public_id: "p_#{SecureRandom.hex(8)}",
      price_cents: 1000, currency: "CNY", product_type: "physical", requires_shipping: true, status: "active"
    )
    item = CartItem.new(product: product)
    standard = Commerce::CalculateShipping.call(subtotal_cents: 1000, cart_items: [ item ], shipping_method_code: "standard")
    express = Commerce::CalculateShipping.call(subtotal_cents: 1000, cart_items: [ item ], shipping_method_code: "express")
    assert standard.success?
    assert express.success?
    assert express.value[:shipping_cents] >= standard.value[:shipping_cents]
  end
end

class Commerce::UpdateOrderShippingTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @admin = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_#{SecureRandom.hex(8)}",
      order_number: "MC#{SecureRandom.hex(4)}",
      user: @user,
      status: "paid",
      subtotal_cents: 1000,
      shipping_cents: 800,
      total_cents: 1800,
      shipping_method: "standard"
    )
    Commerce::OrderItem.create!(
      order: @order,
      product_name: "Physical item",
      unit_price_cents: 1000,
      quantity: 1,
      total_cents: 1000,
      fulfillment_snapshot: { "product_type" => "physical" }
    )
  end

  test "marks order shipped with tracking" do
    result = Commerce::UpdateOrderShipping.call(
      order: @order,
      actor: @admin,
      tracking_number: "SF123456",
      shipping_carrier: "顺丰",
      mark_shipped: true
    )
    assert result.success?, result.error
    @order.reload
    assert_equal "SF123456", @order.tracking_number
    assert @order.shipped_at.present?
  end
end
