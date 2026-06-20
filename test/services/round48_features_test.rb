# frozen_string_literal: true

require "test_helper"

class Community::CloseOwnTopicTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    category = Community::Category.find_or_create_by!(slug: "r48-close") { |c| c.name = "Close" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r48-close-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @user, section: @section, title: "My topic", body: "OP body here", ip_address: "127.0.0.1").value
  end

  test "author can close own topic" do
    result = Community::CloseOwnTopic.call(user: @user, topic: @topic, action: "close")
    assert result.success?, result.error
    assert @topic.reload.locked?
  end

  test "author can reopen own topic" do
    @topic.update!(locked: true)
    result = Community::CloseOwnTopic.call(user: @user, topic: @topic, action: "reopen")
    assert result.success?, result.error
    refute @topic.reload.locked?
  end

  test "other user cannot close topic" do
    other = create_user
    result = Community::CloseOwnTopic.call(user: other, topic: @topic, action: "close")
    assert result.failure?
  end
end

class Community::PostForkBacklinkTest < ActiveSupport::TestCase
  setup do
    @author = create_user
    @forker = create_user
    category = Community::Category.find_or_create_by!(slug: "r48-fork") { |c| c.name = "Fork" }
    @section = Community::Section.find_or_create_by!(category: category, slug: "r48-fork-sec") { |s| s.name = "S"; s.position = 0 }
    @topic = Community::CreateTopic.call(user: @author, section: @section, title: "Source", body: "OP", ip_address: "127.0.0.1").value
    @post = Community::CreatePost.call(user: @author, topic: @topic, body: "Reply", ip_address: "127.0.0.1", skip_interval_check: true).value
    @forked = Community::CreateTopicFromPost.call(user: @forker, post: @post, title: "Forked").value
  end

  test "post lists forked topics" do
    assert_includes @post.reload.forked_topics.pluck(:id), @forked.id
  end
end

class Community::UserCardEnrichmentTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(bio: "Hello bio")
    @viewer = create_user
    sign_in_as(@viewer)
  end

  test "user card includes bio and likes" do
    get card_forum_user_path(@user.username), headers: { "Accept" => "application/json" }
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal "Hello bio", data["bio"]
    assert data.key?("likes_received")
    assert data.key?("online")
  end
end

class Commerce::ValidateShippingAddressTest < ActiveSupport::TestCase
  setup do
    enable_store_feature!(:physical_products)
    enable_store_feature!(:shipping)
    @product = Commerce::Product.create!(
      name: "Ship Product",
      slug: "ship-#{SecureRandom.hex(4)}",
      product_type: "physical",
      status: "active",
      price_cents: 1000,
      currency: "CNY",
      requires_shipping: true,
      fulfillment_config: { shipping_method: "manual" }
    )
    @item = OpenStruct.new(product: @product)
  end

  test "requires address fields for shippable cart" do
    result = Commerce::ValidateShippingAddress.call(cart_items: [ @item ], shipping_address: {})
    assert result.failure?
    assert_includes result.error, "收货地址"
  end

  test "passes with complete address" do
    result = Commerce::ValidateShippingAddress.call(
      cart_items: [ @item ],
      shipping_address: {
        "name" => "张三",
        "phone" => "13800000000",
        "line1" => "路 1 号",
        "city" => "上海",
        "province" => "上海"
      }
    )
    assert result.success?
  end

  test "skips validation for digital-only cart" do
    digital = Commerce::Product.create!(
      name: "Digital",
      slug: "dig-#{SecureRandom.hex(4)}",
      product_type: "digital",
      status: "active",
      price_cents: 500,
      currency: "CNY",
      fulfillment_config: { download_url: "https://example.com/a.zip" }
    )
    result = Commerce::ValidateShippingAddress.call(cart_items: [ OpenStruct.new(product: digital) ], shipping_address: {})
    assert result.success?
  end
end

class Commerce::CheckoutPrefillAddressTest < ActionDispatch::IntegrationTest
  setup do
    enable_store_feature!(:physical_products)
    enable_store_feature!(:shipping)
    @user = create_user
    sign_in_as(@user)
    @product = Commerce::Product.create!(
      name: "Physical Prefill",
      slug: "prefill-#{SecureRandom.hex(4)}",
      product_type: "physical",
      status: "active",
      price_cents: 2000,
      currency: "CNY",
      requires_shipping: true,
      fulfillment_config: { shipping_method: "manual" }
    )
    Commerce::Order.create!(
      public_id: "ord_#{SecureRandom.alphanumeric(16)}",
      order_number: "MC#{Time.current.strftime('%Y%m%d')}#{SecureRandom.hex(4).upcase}",
      user: @user,
      status: "completed",
      currency: "CNY",
      subtotal_cents: 2000,
      total_cents: 2000,
      shipping_address: {
        "name" => "李四",
        "phone" => "13900000000",
        "line1" => "测试街 2 号",
        "city" => "北京",
        "province" => "北京"
      }
    )
    cart = Commerce::Cart.create!(user: @user)
    cart.add_item!(product: @product, quantity: 1)
  end

  test "checkout page includes default shipping address" do
    get store_checkout_path
    assert_response :success
    assert_includes response.body, "李四"
    assert_includes response.body, "测试街 2 号"
  end
end

class Commerce::CartRecoveryBannerTest < ActionDispatch::IntegrationTest
  setup do
    @cart = Commerce::Cart.create!
    @product = Commerce::Product.create!(
      name: "Recovery Banner",
      slug: "rb-#{SecureRandom.hex(4)}",
      product_type: "digital",
      status: "active",
      price_cents: 500,
      currency: "CNY",
      fulfillment_config: { download_url: "https://example.com/a.zip" }
    )
    @cart.add_item!(product: @product, quantity: 1)
    @cart.ensure_recovery_token!
  end

  test "cart show marks recovery" do
    get store_cart_path(recovery: @cart.recovery_token)
    assert_response :success
    assert_includes response.body, '"cartRecovered":true'
  end
end

class Commerce::StoreIndexSeoTest < ActionDispatch::IntegrationTest
  test "store index includes seo title from site setting" do
    SiteSetting.set("store.seo_title", "McWeb 官方商城")
    get store_products_path
    assert_response :success
    assert_includes response.body, "McWeb 官方商城"
  end
end
