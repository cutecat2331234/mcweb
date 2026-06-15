# frozen_string_literal: true

require "test_helper"

class Community::CreateMuteTest < ActiveSupport::TestCase
  test "moderator can mute user" do
    mod = create_user(username: "moduser", email: "mod@example.com")
    grant_permission(mod, "forum.users.mute")
    target = create_user(email: "muted@example.com", username: "muteduser")

    result = Community::CreateMute.call(actor: mod, user: target, reason: "spam")
    assert result.success?
    assert Community::Mute.muted?(target)
  end
end

class Community::ToggleSectionSubscriptionTest < ActiveSupport::TestCase
  test "toggles section watch" do
    user = create_user
    category = Community::Category.find_or_create_by!(slug: "sub-cat") { |c| c.name = "Sub" }
    section = Community::Section.find_or_create_by!(category: category, slug: "sub-sec") do |s|
      s.name = "Sub Sec"
      s.position = 0
    end

    add = Community::ToggleSectionSubscription.call(user: user, section: section)
    assert add.success?
    assert add.value[:watching]
    assert_equal "watching", add.value[:notification_level]

    track = Community::ToggleSectionSubscription.call(user: user, section: section)
    assert track.success?
    assert track.value[:watching]
    assert_equal "tracking", track.value[:notification_level]

    normal = Community::ToggleSectionSubscription.call(user: user, section: section)
    assert normal.success?
    assert normal.value[:watching]
    assert_equal "normal", normal.value[:notification_level]

    remove = Community::ToggleSectionSubscription.call(user: user, section: section)
    assert remove.success?
    assert_not remove.value[:watching]
  end
end

class Community::ModerateTopicFeaturedTest < ActiveSupport::TestCase
  setup do
    @mod = create_user(username: "featmod", email: "featmod@example.com")
    grant_permission(@mod, "forum.topics.lock")
    category = Community::Category.find_or_create_by!(slug: "feat-cat") { |c| c.name = "Feat" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "feat-sec") do |s|
      s.name = "Feat Sec"
      s.position = 0
    end
    @topic = Community::CreateTopic.call(
      user: @mod,
      section: @section,
      title: "Feature me",
      body: "Content",
      ip_address: "127.0.0.1"
    ).value
  end

  test "moderator can feature topic" do
    result = Community::ModerateTopic.call(user: @mod, topic: @topic, action: "feature")
    assert result.success?
    assert @topic.reload.featured?
  end
end

class Commerce::SalesMetricsTest < ActiveSupport::TestCase
  test "returns sales metrics" do
    result = Commerce::SalesMetrics.call
    assert result.success?
    assert result.value.key?(:revenue_cents)
  end
end

class Commerce::CreateReviewPurchaseTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      name: "Review Purchase Product",
      slug: "review-purchase-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      stock: 100
    )
  end

  test "requires purchase to review" do
    result = Commerce::CreateReview.call(user: @user, product: @product, rating: 5)
    assert result.failure?
  end

  test "allows review after purchase" do
    cart = Commerce::Cart.create!(user: @user)
    cart.items.create!(product: @product, quantity: 1)
    order = Commerce::CreateOrder.call(cart: cart, user: @user).value
    order.update!(status: "paid")

    result = Commerce::CreateReview.call(user: @user, product: @product, rating: 5, body: "Good")
    assert result.success?
  end
end
