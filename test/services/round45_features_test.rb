# frozen_string_literal: true

require "test_helper"

class Community::ParseSearchQueryRound45Test < ActiveSupport::TestCase
  test "parses is:unlisted" do
    result = Community::ParseSearchQuery.call(query: "secret is:unlisted")
    assert result.success?
    assert_equal "unlisted", result.value[:unlisted_filter]
    assert_equal "secret", result.value[:query]
  end

  test "parses has:poll and has:noreplies" do
    poll = Community::ParseSearchQuery.call(query: "vote has:poll")
    assert_equal "poll", poll.value[:poll_filter]

    quiet = Community::ParseSearchQuery.call(query: "empty has:noreplies")
    assert_equal "noreplies", quiet.value[:noreplies_filter]
  end
end

class Community::ApplyTopicSearchFiltersRound45Test < ActiveSupport::TestCase
  setup do
    @user = create_user
    @user2 = create_user
    @user3 = create_user
    category = Community::Category.find_or_create_by!(slug: "r45") { |c| c.name = "R45" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r45-sec") { |s| s.name = "S"; s.position = 0 }
    @unlisted = Community::CreateTopic.call(user: @user, section: @section, title: "Hidden", body: "OP hidden", ip_address: "127.0.0.1").value
    @unlisted.update!(unlisted: true)
    @with_poll = Community::CreateTopic.call(user: @user2, section: @section, title: "Poll topic", body: "OP poll", ip_address: "127.0.0.1").value
    Community::Poll.create!(topic: @with_poll, question: "Q?", options: %w[A B], multiple_choice: false)
    @no_reply = Community::CreateTopic.call(user: @user3, section: @section, title: "Lonely", body: "OP alone", ip_address: "127.0.0.1").value
  end

  test "filters unlisted topics" do
    scope = Community::Topic.where(status: :published, unlisted: true)
    result = Community::ApplyTopicSearchFilters.call(scope: scope, unlisted_filter: "unlisted")
    assert_includes result.value.pluck(:id), @unlisted.id
  end

  test "filters poll and no reply topics" do
    scope = Community::Topic.published_listed
    poll_result = Community::ApplyTopicSearchFilters.call(scope: scope, poll_filter: "poll")
    assert_includes poll_result.value.pluck(:id), @with_poll.id

    noreply_result = Community::ApplyTopicSearchFilters.call(scope: scope, noreplies_filter: "noreplies")
    assert_includes noreply_result.value.pluck(:id), @no_reply.id
  end
end

class Community::TrustLevelEditWindowTest < ActiveSupport::TestCase
  test "higher trust gets longer edit window" do
    user = create_user
    category = Community::Category.find_or_create_by!(slug: "r45-trust") { |c| c.name = "T" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r45-trust-sec") { |s| s.name = "S"; s.position = 0 }
    assert_equal 15.minutes, Community::TrustLevel.edit_window_for(user)

    topic = Community::CreateTopic.call(user: user, section: section, title: "Trust", body: "body content", ip_address: "127.0.0.1").value
    assert_equal 1.hour, Community::TrustLevel.edit_window_for(user)

    9.times do |i|
      Community::CreatePost.call(user: user, topic: topic, body: "reply content #{i}", ip_address: "127.0.0.1", skip_interval_check: true)
    end
    assert_equal 24.hours, Community::TrustLevel.edit_window_for(user)
  end
end

class Commerce::MaximumQuantityTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      name: "Max Qty",
      slug: "max-qty-#{SecureRandom.hex(4)}",
      product_type: "digital",
      status: "active",
      price_cents: 1000,
      currency: "CNY",
      minimum_quantity: 1,
      maximum_quantity: 3,
      fulfillment_config: { download_url: "https://example.com/file.zip" }
    )
  end

  test "rejects quantity above maximum" do
    result = Commerce::ValidateCartItem.call(user: @user, product: @product, quantity: 5)
    assert result.failure?
    assert_match(/最多购买/, result.error)
  end

  test "accepts quantity within maximum" do
    result = Commerce::ValidateCartItem.call(user: @user, product: @product, quantity: 2)
    assert result.success?
  end
end

class Commerce::CalculateShippingRound45Test < ActiveSupport::TestCase
  setup do
    enable_store_feature!(:physical_products)
    enable_store_feature!(:shipping)
    SiteSetting.set("store.flat_shipping_cents", "500")
    SiteSetting.set("store.free_shipping_min_order_cents", "0")
    @digital = Commerce::Product.create!(
      name: "Digital",
      slug: "digital-#{SecureRandom.hex(4)}",
      product_type: "digital",
      status: "active",
      price_cents: 1000,
      currency: "CNY",
      requires_shipping: false,
      fulfillment_config: { download_url: "https://example.com/a.zip" }
    )
    @physical = Commerce::Product.create!(
      name: "Physical",
      slug: "physical-#{SecureRandom.hex(4)}",
      product_type: "physical",
      status: "active",
      price_cents: 2000,
      currency: "CNY",
      requires_shipping: true,
      fulfillment_config: {}
    )
    @cart = Commerce::Cart.create!(user: create_user)
    @cart.add_item!(product: @digital, quantity: 1)
  end

  test "digital-only cart has no shipping" do
    items = @cart.items.includes(:product)
    result = Commerce::CalculateShipping.call(subtotal_cents: 1000, cart_items: items)
    assert result.success?
    assert_equal 0, result.value[:shipping_cents]
    assert result.value[:no_shippable_items]
  end

  test "free shipping coupon zeros shipping" do
    @cart.add_item!(product: @physical, quantity: 1)
    coupon = Commerce::Coupon.create!(
      code: "FREESHIP#{SecureRandom.hex(3).upcase}",
      discount_type: "percentage",
      discount_value: 10,
      free_shipping: true,
      active: true
    )
    items = @cart.items.includes(:product)
    result = Commerce::CalculateShipping.call(subtotal_cents: 3000, cart_items: items, coupon: coupon)
    assert_equal 0, result.value[:shipping_cents]
    assert result.value[:coupon_free_shipping]
  end
end

class Commerce::PreviewCouponFreeShippingTest < ActiveSupport::TestCase
  test "preview includes free shipping total" do
    enable_store_feature!(:physical_products)
    enable_store_feature!(:shipping)
    SiteSetting.set("store.flat_shipping_cents", "800")
    product = Commerce::Product.create!(
      name: "Ship",
      slug: "ship-#{SecureRandom.hex(4)}",
      product_type: "physical",
      status: "active",
      price_cents: 5000,
      currency: "CNY",
      requires_shipping: true,
      fulfillment_config: {}
    )
    cart = Commerce::Cart.create!(user: create_user)
    cart.add_item!(product: product, quantity: 1)
    coupon = Commerce::Coupon.create!(
      code: "SHIPFREE#{SecureRandom.hex(3).upcase}",
      discount_type: "fixed",
      discount_value: 100,
      free_shipping: true,
      active: true
    )
    result = Commerce::PreviewCoupon.call(
      subtotal_cents: 5000,
      code: coupon.code,
      cart_items: cart.items.includes(:product),
      user: cart.user
    )
    assert result.success?
    assert result.value[:free_shipping]
    assert_equal 0, result.value[:shipping_cents]
    assert_equal 4900, result.value[:total_cents]
  end
end
