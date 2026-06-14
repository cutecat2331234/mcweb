# frozen_string_literal: true

require "test_helper"

class Community::SavedSearchTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @search = Community::SavedSearch.create!(
      user: @user,
      name: "未解决帖",
      query: "help is:unsolved",
      filters: { "solved" => "unsolved" }
    )
  end

  test "saved search stores filters" do
    assert_equal "help is:unsolved", @search.query
    assert_equal "unsolved", @search.filters["solved"]
  end
end

class Community::UserCardTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    sign_in_as(@user)
    @target = create_user
  end

  test "user card returns json" do
    get card_forum_user_path(@target.username), headers: { "Accept" => "application/json" }
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal @target.username, data["username"]
    assert data["profile_url"].present?
  end
end

class Community::MessageSearchTest < ActionDispatch::IntegrationTest
  setup do
    @sender = create_user
    @recipient = create_user
    category = Community::Category.find_or_create_by!(slug: "r46-pm") { |c| c.name = "PM" }
    section = Community::Section.find_or_create_by!(category: category, slug: "r46-pm-sec") { |s| s.name = "S"; s.position = 0 }
    Community::CreateTopic.call(user: @sender, section: section, title: "PM unlock", body: "unlock post", ip_address: "127.0.0.1")
    sign_in_as(@sender)
    result = Community::CreateConversation.call(
      sender: @sender,
      recipient_username: @recipient.username,
      body: "unique secret keyword xyz"
    )
    assert result.success?, result.error
    @conversation = result.value[:conversation]
  end

  test "filters conversations by message body" do
    get forum_conversations_path(q: "unique secret keyword")
    assert_response :success
    assert_includes response.body, @conversation.display_name(@sender)
  end
end

class Commerce::ProductSeoTest < ActiveSupport::TestCase
  test "product stores seo metadata" do
    product = Commerce::Product.create!(
      name: "SEO Product",
      slug: "seo-#{SecureRandom.hex(4)}",
      product_type: "digital",
      status: "active",
      price_cents: 1000,
      currency: "CNY",
      seo: { "title" => "Custom Title", "description" => "Custom description" },
      fulfillment_config: { download_url: "https://example.com/a.zip" }
    )
    assert_equal "Custom Title", product.seo["title"]
  end
end

class Commerce::CartMaxItemsTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @cart = Commerce::Cart.create!(user: @user)
    @product = Commerce::Product.create!(
      name: "Cart Limit",
      slug: "cart-limit-#{SecureRandom.hex(4)}",
      product_type: "digital",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      fulfillment_config: { download_url: "https://example.com/a.zip" }
    )
    @prev = SiteSetting.get("store.cart_max_items")
    SiteSetting.set("store.cart_max_items", "3")
  end

  teardown do
    SiteSetting.set("store.cart_max_items", @prev) if @prev
  end

  test "rejects cart above max items" do
    result = Commerce::ValidateCartItem.call(user: @user, product: @product, quantity: 5, cart: @cart, replace_quantity: true)
    assert result.failure?
    assert_match(/购物车最多/, result.error)
  end
end

class Commerce::StoreSitemapTest < ActionDispatch::IntegrationTest
  test "store sitemap returns xml" do
    Commerce::Product.create!(
      name: "Sitemap Product",
      slug: "sitemap-#{SecureRandom.hex(4)}",
      product_type: "digital",
      status: "active",
      price_cents: 1000,
      currency: "CNY",
      fulfillment_config: { download_url: "https://example.com/a.zip" }
    )
    get store_sitemap_path
    assert_response :success
    assert_includes response.body, "<urlset"
    assert_includes response.body, "/store/products/"
  end
end

class Commerce::QuickAddableProductTest < ActiveSupport::TestCase
  test "product without variants is quick addable when purchasable" do
    product = Commerce::Product.create!(
      name: "Quick",
      slug: "quick-#{SecureRandom.hex(4)}",
      product_type: "digital",
      status: "active",
      price_cents: 500,
      currency: "CNY",
      fulfillment_config: { download_url: "https://example.com/a.zip" }
    )
    assert product.variants.none?
    assert product.purchasable?
  end
end
