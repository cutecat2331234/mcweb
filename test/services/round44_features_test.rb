# frozen_string_literal: true

require "test_helper"

class Community::ParseSearchQueryFeaturedTest < ActiveSupport::TestCase
  test "parses is:featured" do
    result = Community::ParseSearchQuery.call(query: "hot is:featured")
    assert result.success?
    assert_equal "featured", result.value[:featured_filter]
  end

  test "parses is:announcement and is:global alias" do
    result = Community::ParseSearchQuery.call(query: "news is:announcement")
    assert_equal "announcement", result.value[:announcement_filter]

    global = Community::ParseSearchQuery.call(query: "is:global")
    assert_equal "announcement", global.value[:announcement_filter]
  end
end

class Community::ApplyTopicSearchFiltersFeaturedTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @user2 = create_user
    category = Community::Category.find_or_create_by!(slug: "r44-feat") { |c| c.name = "F" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r44-feat-sec") { |s| s.name = "S"; s.position = 0 }
    @featured = Community::CreateTopic.call(user: @user, section: section, title: "Feat", body: "OP", ip_address: "127.0.0.1").value
    @featured.update!(featured: true)
    @announce = Community::CreateTopic.call(user: @user2, section: section, title: "Ann", body: "OP2", ip_address: "127.0.0.1").value
    @announce.update!(global_announcement: true)
  end

  test "filters featured topics" do
    scope = Community::Topic.published_listed
    result = Community::ApplyTopicSearchFilters.call(scope: scope, featured_filter: "featured")
    assert_includes result.value.pluck(:id), @featured.id
  end

  test "filters announcement topics" do
    scope = Community::Topic.published_listed
    result = Community::ApplyTopicSearchFilters.call(scope: scope, announcement_filter: "announcement")
    assert_includes result.value.pluck(:id), @announce.id
  end
end

class Community::SectionLinkTest < ActiveSupport::TestCase
  test "section accepts external link" do
    category = Community::Category.find_or_create_by!(slug: "r44-link") { |c| c.name = "L" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r44-link-sec") do |s|
      s.name = "Link"
      s.position = 0
      s.link_url = "https://example.com/rules"
      s.link_label = "版规"
    end
    assert_equal "https://example.com/rules", section.link_url
    assert_equal "版规", section.link_label
  end
end

class Commerce::MinimumQuantityTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      name: "Bulk Product",
      slug: "bulk-#{SecureRandom.hex(4)}",
      product_type: "digital",
      price_cents: 1000,
      currency: "CNY",
      status: "active",
      stock: 100,
      minimum_quantity: 3
    )
  end

  test "rejects below minimum quantity" do
    result = Commerce::ValidateCartItem.call(user: @user, product: @product, quantity: 2)
    assert result.failure?
    assert_match(/最少购买/, result.error)
  end

  test "allows at minimum quantity" do
    cart = Commerce::Cart.create!(user: @user)
    result = Commerce::ValidateCartItem.call(user: @user, product: @product, quantity: 3, cart: cart)
    assert result.success?
  end
end

class Commerce::PurchaseLimitRemainingTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      name: "Limited Product",
      slug: "lim-#{SecureRandom.hex(4)}",
      product_type: "digital",
      price_cents: 500,
      currency: "CNY",
      status: "active",
      purchase_limit: 5
    )
    order = Commerce::Order.create!(
      public_id: "ord_#{SecureRandom.alphanumeric(16)}",
      user: @user,
      order_number: "ORD#{SecureRandom.hex(6).upcase}",
      status: "paid",
      subtotal_cents: 500,
      total_cents: 500,
      currency: "CNY"
    )
    Commerce::OrderItem.create!(
      order: order,
      product: @product,
      product_name: @product.name,
      quantity: 2,
      unit_price_cents: 500,
      total_cents: 1000
    )
  end

  test "calculates remaining purchase limit" do
    result = Commerce::PurchaseLimitRemaining.call(user: @user, product: @product)
    assert result.success?
    assert_equal 3, result.value[:remaining]
    assert_equal 5, result.value[:limit]
  end
end
