# frozen_string_literal: true

require "test_helper"

# Regression tests for bugs found in the adversarially-verified re-check pass.
class CreateReviewModerationBypassTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      public_id: "prod_rev_#{SecureRandom.hex(4)}",
      name: "Reviewable",
      slug: "reviewable-#{SecureRandom.hex(3)}",
      product_type: "digital",
      status: "active",
      price_cents: 100,
      currency: "CNY"
    )
    order = Commerce::Order.create!(
      public_id: "ord_rev_#{SecureRandom.hex(4)}",
      order_number: "ORD-REV-#{SecureRandom.hex(3)}",
      user: @user,
      status: "paid",
      subtotal_cents: 100,
      total_cents: 100,
      currency: "CNY"
    )
    Commerce::OrderItem.create!(
      order: order,
      store_product_id: @product.id,
      product_name: @product.name,
      unit_price_cents: 100,
      quantity: 1,
      total_cents: 100
    )
  end

  test "resubmitting a moderator-hidden review does not republish it" do
    review = Commerce::CreateReview.call(user: @user, product: @product, rating: 5, body: "great").value
    assert_equal "published", review.status

    review.update!(status: :hidden) # moderator (or DeleteReview) hides it

    result = Commerce::CreateReview.call(user: @user, product: @product, rating: 1, body: "abusive resubmit")
    assert result.success?
    assert_equal "hidden", review.reload.status, "a hidden review must stay hidden on resubmit"
  end

  test "a normal resubmit of a still-published review stays published" do
    review = Commerce::CreateReview.call(user: @user, product: @product, rating: 4, body: "ok").value
    Commerce::CreateReview.call(user: @user, product: @product, rating: 5, body: "updated")
    assert_equal "published", review.reload.status
  end
end

class ToggleConversationMuteIdempotentTest < ActiveSupport::TestCase
  setup do
    @alice = create_user
    enable_forum_pm!(@alice)
    @bob = create_user
    enable_forum_pm!(@bob)
    @conversation = Community::CreateConversation.call(
      sender: @alice,
      recipient_username: @bob.username,
      body: "Hello"
    ).value[:conversation]
  end

  test "mute endpoint is idempotent and unmute clears it" do
    2.times { Community::ToggleConversationMute.call(user: @alice, conversation: @conversation, muted: true) }
    participant = @conversation.participants.find_by(user: @alice)
    assert participant.muted_at.present?, "muting twice must keep it muted, not toggle back"

    2.times { Community::ToggleConversationMute.call(user: @alice, conversation: @conversation, muted: false) }
    assert_nil participant.reload.muted_at, "unmuting must clear mute and stay cleared"
  end

  test "no explicit state still toggles (backward compatible)" do
    Community::ToggleConversationMute.call(user: @alice, conversation: @conversation)
    participant = @conversation.participants.find_by(user: @alice)
    assert participant.muted_at.present?
    Community::ToggleConversationMute.call(user: @alice, conversation: @conversation)
    assert_nil participant.reload.muted_at
  end
end

class UrlSafetyPublicIpTest < ActiveSupport::TestCase
  test "unspecified, loopback, private and reserved addresses are not public" do
    %w[0.0.0.0 :: 127.0.0.1 ::1 10.0.0.1 172.16.0.1 192.168.1.1 169.254.169.254 240.0.0.1].each do |addr|
      assert_not UrlSafety.send(:public_ip?, IPAddr.new(addr)), "#{addr} must not be treated as public"
    end
  end

  test "genuine public addresses are allowed" do
    %w[8.8.8.8 1.1.1.1 2606:4700:4700::1111].each do |addr|
      assert UrlSafety.send(:public_ip?, IPAddr.new(addr)), "#{addr} should be public"
    end
  end
end
