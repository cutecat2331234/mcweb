# frozen_string_literal: true

require "test_helper"

class Commerce::StoreFeaturesTest < ActiveSupport::TestCase
  teardown do
    Commerce::StoreFeatures.definitions.each do |definition|
      SiteSetting.set(definition.key, "false")
    end
  end

  test "features default to disabled" do
    Commerce::StoreFeatures.definitions.each do |definition|
      SiteSetting.where(key: definition.key).delete_all
      assert_not Commerce::StoreFeatures.enabled?(definition.id), "#{definition.id} should default off"
    end
  end

  test "frontend_hash reflects site settings" do
    SiteSetting.set("store.features.shipping", "true")
    SiteSetting.set("store.features.gift_wrap", "true")

    hash = Commerce::StoreFeatures.frontend_hash
    assert hash["shipping"]
    assert hash["gift_wrap"]
    assert_not hash["physical_products"]
    assert_not hash["order_shipping_management"]
  end
end

class Commerce::StoreFeaturesCreateOrderTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @product = Commerce::Product.create!(
      name: "Virtual Item",
      slug: "virtual-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 2000,
      currency: "CNY",
      requires_shipping: false,
      fulfillment_config: {}
    )
    @cart = Commerce::Cart.create!(user: @user)
    @cart.add_item!(product: @product, quantity: 1)
    @address = {
      "name" => "张三",
      "phone" => "13800000000",
      "line1" => "测试路 1 号",
      "city" => "上海",
      "province" => "上海"
    }
  end

  teardown do
    Commerce::StoreFeatures.definitions.each do |definition|
      SiteSetting.set(definition.key, "false")
    end
  end

  test "create order ignores shipping when feature disabled" do
    result = Commerce::CreateOrder.call(
      cart: @cart.reload,
      user: @user,
      shipping_address: @address,
      shipping_method: "express",
      gift_wrap: true
    )

    assert result.success?, result.error
    order = result.value
    assert_equal({}, order.shipping_address)
    assert_nil order.shipping_method
    assert_equal 0, order.shipping_cents
    assert_not order.gift_wrap?
    assert_equal 0, order.gift_wrap_cents
  end

  test "create order saves shipping when feature enabled" do
    SiteSetting.set("store.features.physical_products", "true")
    SiteSetting.set("store.features.shipping", "true")
    SiteSetting.set("store.features.gift_wrap", "true")
    SiteSetting.set("store.gift_wrap_cents", "500")

    physical = Commerce::Product.create!(
      name: "Physical Item",
      slug: "physical-#{SecureRandom.hex(4)}",
      product_type: "physical",
      status: "active",
      price_cents: 2000,
      currency: "CNY",
      requires_shipping: true,
      fulfillment_config: { shipping_method: "manual" }
    )
    cart = Commerce::Cart.create!(user: create_user)
    cart.add_item!(product: physical, quantity: 1)

    result = Commerce::CreateOrder.call(
      cart: cart,
      user: cart.user,
      shipping_address: @address,
      shipping_method: "standard",
      gift_wrap: true
    )

    assert result.success?, result.error
    order = result.value
    assert_equal "张三", order.shipping_address["name"]
    assert_equal "standard", order.shipping_method
    assert order.gift_wrap?
    assert_equal 500, order.gift_wrap_cents
  end
end

class Commerce::StoreFeaturesCheckoutIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    disable_store_features!
    @user = create_user
    @product = Commerce::Product.create!(
      name: "Virtual",
      slug: "virt-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 1500,
      currency: "CNY",
      requires_shipping: false,
      fulfillment_config: {}
    )
    cart = Commerce::Cart.create!(user: @user)
    cart.add_item!(product: @product, quantity: 1)
    sign_in_as(@user)
  end

  teardown do
    Commerce::StoreFeatures.definitions.each do |definition|
      SiteSetting.set(definition.key, "false")
    end
  end

  test "checkout omits shipping props when shipping disabled" do
    get store_checkout_path
    assert_response :success
    refute_includes response.body, '"requiresShipping"'
    refute_includes response.body, '"shippingMethods"'
    refute_includes response.body, '"shippingAddressesUrl"'
    refute_includes response.body, '"giftWrapAvailable"'
  end

  test "checkout includes shipping props when shipping enabled" do
    enable_store_feature!(:shipping)
    shippable = Commerce::Product.create!(
      name: "Shippable",
      slug: "ship-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 1500,
      currency: "CNY",
      requires_shipping: true,
      fulfillment_config: {}
    )
    cart = Commerce::Cart.find_by(user: @user)
    cart.items.destroy_all
    cart.add_item!(product: shippable, quantity: 1)

    get store_checkout_path
    assert_response :success
    assert_includes response.body, '"requiresShipping"'
    assert_includes response.body, '"shippingMethods"'
    assert_includes response.body, '"shippingAddressesUrl"'
  end

  test "inertia share includes storeFeatures when store enabled" do
    SiteSetting.set("store.features.shipping", "true")

    get store_products_path
    assert_response :success
    assert_includes response.body, '"storeFeatures"'
    assert_includes response.body, '"shipping":true'
    assert_includes response.body, '"physical_products":false'
  end

  test "shipping addresses return 404 when shipping disabled" do
    get store_shipping_addresses_path
    assert_response :not_found
  end

  test "shipping addresses accessible when shipping enabled" do
    SiteSetting.set("store.features.shipping", "true")

    get store_shipping_addresses_path
    assert_response :success
  end
end

class Commerce::StoreFeaturesUpdateOrderShippingTest < ActiveSupport::TestCase
  setup do
    @admin = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_sf_#{SecureRandom.hex(6)}",
      order_number: "SF#{SecureRandom.hex(4)}",
      user: @admin,
      status: "paid",
      subtotal_cents: 1000,
      total_cents: 1000,
      currency: "CNY"
    )
    Commerce::OrderItem.create!(
      order: @order,
      product: Commerce::Product.create!(
        name: "Physical",
        slug: "phys-#{SecureRandom.hex(4)}",
        product_type: "physical",
        status: "active",
        price_cents: 1000,
        currency: "CNY",
        fulfillment_config: {}
      ),
      product_name: "Physical",
      unit_price_cents: 1000,
      quantity: 1,
      total_cents: 1000,
      fulfillment_snapshot: { product_type: "physical" }
    )
  end

  teardown do
    Commerce::StoreFeatures.definitions.each do |definition|
      SiteSetting.set(definition.key, "false")
    end
  end

  test "update order shipping rejected when management disabled" do
    result = Commerce::UpdateOrderShipping.call(
      order: @order,
      actor: @admin,
      tracking_number: "SF123",
      mark_shipped: true
    )

    assert result.failure?
    assert_includes result.error, "物流管理"
  end
end

class Commerce::StoreFeaturesSerializationTest < ActiveSupport::TestCase
  setup do
    disable_store_features!
    @virtual = Commerce::Product.create!(
      public_id: "prod_ser_virt_#{SecureRandom.hex(4)}",
      name: "Visible Virtual",
      slug: "ser-virt-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      requires_shipping: false
    )
    @physical = Commerce::Product.create!(
      public_id: "prod_ser_phys_#{SecureRandom.hex(4)}",
      name: "Hidden Physical",
      slug: "ser-phys-#{SecureRandom.hex(4)}",
      product_type: "physical",
      status: "active",
      price_cents: 100,
      currency: "CNY"
    )
    @helper = Class.new do
      include InertiaSerializable
      include Rails.application.routes.url_helpers

      attr_accessor :session

      def initialize
        @session = {}
      end
    end.new
  end

  test "compare_product_count excludes hidden products" do
    @helper.session[:compare_product_ids] = [ @virtual.public_id, @physical.public_id ]
    assert_equal 1, @helper.send(:compare_product_count)
  end

  test "linked_product_props omits hidden products" do
    category = Community::Category.find_or_create_by!(slug: "sf-link-cat") { |c| c.name = "SF Link" }
    section = Community::Section.find_or_create_by!(category: category, slug: "sf-link-sec") do |s|
      s.name = "SF Link"
      s.position = 0
    end
    user = create_user
    topic = Community::Topic.create!(
      public_id: "topic_sf_#{SecureRandom.alphanumeric(16)}",
      section: section,
      user: user,
      title: "Linked product topic",
      status: "published",
      last_posted_at: Time.current,
      last_post_user: user,
      replies_count: 0
    )
    @physical.update!(forum_topic_id: topic.id)

    props = @helper.send(:linked_product_props, topic)
    assert_equal({}, props)
  end
end

class Commerce::StoreFeaturesAdminProductUpdateTest < ActionDispatch::IntegrationTest
  setup do
    disable_store_features!
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "store.products.manage")
    sign_in_as(@admin)
    @product = Commerce::Product.create!(
      public_id: "prod_admin_sf_#{SecureRandom.hex(4)}",
      name: "Admin Virtual",
      slug: "admin-virt-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 500,
      currency: "CNY",
      requires_shipping: false,
      fulfillment_config: {}
    )
  end

  test "admin update strips requires_shipping when shipping disabled" do
    patch admin_store_product_path(@product), params: {
      product: {
        name: @product.name,
        slug: @product.slug,
        description: @product.description.to_s,
        product_type: "virtual",
        status: "active",
        price_cents: 500,
        currency: "CNY",
        requires_shipping: true,
        fulfillment_config: "{}"
      }
    }

    assert_redirected_to admin_store_product_path(@product)
    assert_not @product.reload.requires_shipping?
  end
end

class Commerce::StoreFeaturesReorderTest < ActiveSupport::TestCase
  setup do
    disable_store_features!
    @user = create_user
    @virtual = Commerce::Product.create!(
      name: "Virtual Reorder",
      slug: "reorder-virt-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 500,
      currency: "CNY",
      stock: 10
    )
    @physical = Commerce::Product.create!(
      name: "Physical Reorder",
      slug: "reorder-phys-#{SecureRandom.hex(4)}",
      product_type: "physical",
      status: "active",
      price_cents: 500,
      currency: "CNY",
      stock: 10
    )
    [ @virtual, @physical ].each do |product|
      order = Commerce::Order.create!(
        user: @user,
        order_number: "ORD-#{SecureRandom.hex(4)}",
        status: "paid",
        subtotal_cents: 500,
        total_cents: 500,
        currency: "CNY"
      )
      Commerce::OrderItem.create!(
        order: order,
        product: product,
        product_name: product.name,
        unit_price_cents: 500,
        quantity: 1,
        total_cents: 500
      )
    end
  end

  test "reorder product rejects hidden physical products" do
    result = Commerce::ReorderProduct.call(user: @user, product: @physical)
    assert result.failure?
    assert_equal "当前商品不可购买。", result.error
  end

  test "reorder product allows visible virtual products" do
    result = Commerce::ReorderProduct.call(user: @user, product: @virtual)
    assert result.success?, result.error
  end
end

class Commerce::StoreFeaturesWishlistCartTest < ActiveSupport::TestCase
  setup do
    disable_store_features!
    @user = create_user
    @virtual = Commerce::Product.create!(
      name: "Wishlist Virtual",
      slug: "wl-virt-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 300,
      currency: "CNY",
      stock: 10
    )
    @physical = Commerce::Product.create!(
      name: "Wishlist Physical",
      slug: "wl-phys-#{SecureRandom.hex(4)}",
      product_type: "physical",
      status: "active",
      price_cents: 300,
      currency: "CNY",
      stock: 10
    )
    Commerce::WishlistItem.create!(user: @user, product: @virtual)
    Commerce::WishlistItem.create!(user: @user, product: @physical)
  end

  test "add wishlist to cart skips hidden products" do
    result = Commerce::AddWishlistToCart.call(user: @user)
    assert result.success?
    assert_equal 1, result.value[:added]
    assert_includes result.value[:skipped].join, @physical.name
  end
end

class Commerce::StoreFeaturesVirtualShippingTest < ActiveSupport::TestCase
  setup do
    disable_store_features!
    enable_store_feature!(:shipping)
    @shippable_virtual = Commerce::Product.create!(
      name: "Shippable Virtual",
      slug: "ship-virt-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 500,
      currency: "CNY",
      requires_shipping: true
    )
    @physical = Commerce::Product.create!(
      name: "Physical Only",
      slug: "phys-only-#{SecureRandom.hex(4)}",
      product_type: "physical",
      status: "active",
      price_cents: 500,
      currency: "CNY",
      requires_shipping: false
    )
  end

  teardown do
    disable_store_features!
  end

  test "product_visible allows virtual requires_shipping when only shipping enabled" do
    assert Commerce::StoreFeatures.product_visible?(@shippable_virtual)
    assert_not Commerce::StoreFeatures.product_visible?(@physical)
  end

  test "visible_products_scope hides physical products when shipping disabled" do
    ids = Commerce::StoreFeatures.visible_products_scope(
      Commerce::Product.where(id: [ @shippable_virtual.id, @physical.id ])
    ).pluck(:id)
    assert_equal [ @shippable_virtual.id ], ids

    disable_store_features!
    ids = Commerce::StoreFeatures.visible_products_scope(
      Commerce::Product.where(id: [ @shippable_virtual.id, @physical.id ])
    ).pluck(:id)
    assert_empty ids
  end
end

class Commerce::StoreFeaturesUpcomingTest < ActionDispatch::IntegrationTest
  setup do
    disable_store_features!
    @physical = Commerce::Product.create!(
      name: "Upcoming Physical #{SecureRandom.hex(3)}",
      slug: "up-phys-#{SecureRandom.hex(4)}",
      product_type: "physical",
      status: "active",
      price_cents: 500,
      currency: "CNY",
      available_at: 1.week.from_now
    )
    @virtual = Commerce::Product.create!(
      name: "Upcoming Virtual #{SecureRandom.hex(3)}",
      slug: "up-virt-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 500,
      currency: "CNY",
      available_at: 1.week.from_now
    )
  end

  teardown do
    disable_store_features!
  end

  test "index upcoming section hides physical when physical_products disabled" do
    get store_products_path
    assert_response :success
    assert_includes response.body, @virtual.name
    assert_not_includes response.body, @physical.name
  end

  test "availability alert create rejects hidden upcoming product" do
    user = create_user
    sign_in_as(user)

    post availability_alert_store_product_path(@physical)
    assert_response :not_found
  end
end

class Commerce::StoreFeaturesAdminVirtualShippingTest < ActionDispatch::IntegrationTest
  setup do
    disable_store_features!
    enable_store_feature!(:shipping)
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "store.products.manage")
    sign_in_as(@admin)
  end

  teardown do
    disable_store_features!
  end

  test "admin create keeps requires_shipping on virtual when shipping enabled without physical_products" do
    slug = "virt-ship-only-#{SecureRandom.hex(4)}"
    assert_difference -> { Commerce::Product.count }, 1 do
      post admin_store_products_path, params: {
        product: {
          name: "Virtual Ship",
          slug: slug,
          product_type: "virtual",
          status: "active",
          price_cents: 500,
          currency: "CNY",
          requires_shipping: true,
          fulfillment_config: "{}"
        }
      }
    end

    product = Commerce::Product.find_by!(slug: slug)
    assert product.requires_shipping?
    assert_equal "virtual", product.product_type
  end
end
