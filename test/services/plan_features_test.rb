# frozen_string_literal: true

require "test_helper"

class Commerce::StoreFeaturesPlanTest < ActiveSupport::TestCase
  setup do
    @previous = Commerce::StoreFeatures.definitions.to_h do |definition|
      [ definition.key, SiteSetting.get(definition.key) ]
    end
    Commerce::StoreFeatures.definitions.each do |definition|
      SiteSetting.set(definition.key, definition.default ? "true" : "false")
    end
  end

  teardown do
    @previous.each do |key, value|
      SiteSetting.set(key, value || "")
    end
  end

  test "defaults all store features to disabled" do
    hash = Commerce::StoreFeatures.frontend_hash

    assert_equal(
      {
        "physical_products" => false,
        "shipping" => false,
        "gift_wrap" => false,
        "order_shipping_management" => false
      },
      hash
    )
    Commerce::StoreFeatures.definitions.each do |definition|
      assert_not Commerce::StoreFeatures.enabled?(definition.id), "#{definition.id} should be disabled by default"
    end
  end

  test "enables individual features from site settings" do
    SiteSetting.set("store.features.shipping", "true")
    SiteSetting.set("store.features.gift_wrap", "1")

    assert Commerce::StoreFeatures.enabled?(:shipping)
    assert Commerce::StoreFeatures.enabled?(:gift_wrap)
    assert_not Commerce::StoreFeatures.enabled?(:physical_products)

    assert_equal true, Commerce::StoreFeatures.frontend_hash["shipping"]
    assert_equal true, Commerce::StoreFeatures.frontend_hash["gift_wrap"]
  end

  test "update_from_params persists toggles" do
    result = Commerce::StoreFeatures.update_from_params!(
      {
        "physical_products" => "true",
        "shipping" => "false",
        "order_shipping_management" => "1"
      }
    )

    assert result.success?
    assert Commerce::StoreFeatures.enabled?(:physical_products)
    assert_not Commerce::StoreFeatures.enabled?(:shipping)
    assert Commerce::StoreFeatures.enabled?(:order_shipping_management)
  end

  test "admin_props reflect current enabled state" do
    SiteSetting.set("store.features.physical_products", "true")

    props = Commerce::StoreFeatures.admin_props.index_by { |row| row[:id] }

    assert props["physical_products"][:enabled]
    assert_not props["shipping"][:enabled]
  end
end

class Commerce::StoreFeaturesAdminOrderPropsTest < ActionDispatch::IntegrationTest
  setup do
    disable_store_features!
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "store.orders.read")
    @user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_admin_feat_#{SecureRandom.hex(4)}",
      order_number: "ADM#{SecureRandom.hex(3).upcase}",
      user: @user,
      status: "paid",
      subtotal_cents: 1000,
      shipping_cents: 100,
      total_cents: 1100,
      currency: "CNY",
      shipping_address: { "name" => "Test", "line1" => "Addr" },
      shipping_method: "standard",
      tracking_number: "TRACK123",
      shipping_carrier: "SF"
    )
  end

  test "admin order omits shipping fields when features disabled" do
    sign_in_as(@admin)
    get admin_store_order_path(@order)
    assert_response :success
    refute_includes response.body, "收货地址"
    refute_includes response.body, "物流单号"
    refute_includes response.body, "shippingManagement"
    assert_includes response.body, '"shippingForm":null'
  end

  test "admin order includes shipping form when order_shipping_management enabled" do
    enable_store_feature!(:order_shipping_management)
    sign_in_as(@admin)
    get admin_store_order_path(@order)
    assert_response :success
    assert_includes response.body, "物流单号"
    assert_includes response.body, '"shippingForm"'
    assert_includes response.body, "TRACK123"
  end
end

class Commerce::StoreFeaturesOrderDetailPropsTest < ActionDispatch::IntegrationTest
  setup do
    disable_store_features!
    @user = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_detail_feat_#{SecureRandom.hex(4)}",
      order_number: "DET#{SecureRandom.hex(3).upcase}",
      user: @user,
      status: "paid",
      subtotal_cents: 1000,
      total_cents: 1000,
      currency: "CNY",
      tracking_number: "TRK1"
    )
  end

  test "order detail omits shipping props when features disabled" do
    sign_in_as(@user)
    get store_order_path(@order)
    assert_response :success
    refute_includes response.body, '"tracking_number"'
    refute_includes response.body, '"packing_slip_url"'
    refute_includes response.body, '"shipping_address_label"'
  end
end

class Commerce::StoreFeaturesCouponTest < ActionDispatch::IntegrationTest
  setup do
    disable_store_features!
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "store.products.manage")
  end

  test "coupon create clears free_shipping when shipping disabled" do
    sign_in_as(@admin)
    assert_difference -> { Commerce::Coupon.count }, 1 do
      post admin_store_coupons_path, params: {
        coupon: {
          code: "FREESHIP#{SecureRandom.hex(2).upcase}",
          discount_type: "percentage",
          discount_value: 10,
          min_amount_cents: 0,
          active: true,
          free_shipping: true
        }
      }
    end

    assert_redirected_to %r{/admin/store/coupons/}
    assert_not Commerce::Coupon.order(:id).last.free_shipping?
  end

  test "coupon create allows free_shipping when shipping enabled" do
    enable_store_feature!(:shipping)
    sign_in_as(@admin)

    post admin_store_coupons_path, params: {
      coupon: {
        code: "SHIP#{SecureRandom.hex(2).upcase}",
        discount_type: "percentage",
        discount_value: 10,
        min_amount_cents: 0,
        active: true,
        free_shipping: true
      }
    }

    assert_redirected_to %r{/admin/store/coupons/}
    assert Commerce::Coupon.order(:id).last.free_shipping?
  end
end

class Commerce::StoreFeaturesProductVisibilityTest < ActiveSupport::TestCase
  setup do
    disable_store_features!
    @virtual = Commerce::Product.create!(
      public_id: "prod_vis_virt_#{SecureRandom.hex(4)}",
      name: "Virtual",
      slug: "virtual-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY"
    )
    @physical = Commerce::Product.create!(
      public_id: "prod_vis_phys_#{SecureRandom.hex(4)}",
      name: "Physical",
      slug: "physical-#{SecureRandom.hex(4)}",
      product_type: "physical",
      status: "active",
      price_cents: 100,
      currency: "CNY"
    )
    @shippable = Commerce::Product.create!(
      public_id: "prod_vis_ship_#{SecureRandom.hex(4)}",
      name: "Shippable",
      slug: "shippable-#{SecureRandom.hex(4)}",
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY",
      requires_shipping: true
    )
  end

  test "product_visible rejects physical when feature disabled" do
    assert_not Commerce::StoreFeatures.product_visible?(@physical)
    assert Commerce::StoreFeatures.product_visible?(@virtual)
  end

  test "product_visible rejects requires_shipping when shipping disabled" do
    assert_not Commerce::StoreFeatures.product_visible?(@shippable)
    enable_store_feature!(:shipping)
    assert Commerce::StoreFeatures.product_visible?(@shippable)
  end

  test "visible_products_scope hides physical and shippable by default" do
    ids = Commerce::StoreFeatures.visible_products_scope(Commerce::Product.where(id: [ @virtual.id, @physical.id, @shippable.id ])).pluck(:id)
    assert_equal [ @virtual.id ], ids
  end

  test "validate cart item rejects physical when feature disabled" do
    user = create_user
    result = Commerce::ValidateCartItem.call(user: user, product: @physical, quantity: 1)
    assert result.failure?
    assert_match(/实体商品/, result.error.to_s)
  end
end

class Commerce::StoreFeaturesProductCatalogTest < ActionDispatch::IntegrationTest
  setup do
    disable_store_features!
    @user = create_user
    @physical = Commerce::Product.create!(
      public_id: "prod_cat_phys_#{SecureRandom.hex(4)}",
      name: "Hidden Physical",
      slug: "hidden-physical-#{SecureRandom.hex(4)}",
      product_type: "physical",
      status: "active",
      price_cents: 100,
      currency: "CNY"
    )
    sign_in_as(@user)
  end

  test "physical product page returns not found when feature disabled" do
    get store_product_path(@physical)
    assert_response :not_found
  end

  test "store index omits physical products when feature disabled" do
    get store_products_path
    assert_response :success
    refute_includes response.body, @physical.public_id
  end

  test "category page omits physical products when feature disabled" do
    category = Commerce::Category.create!(
      name: "Test Cat",
      slug: "test-cat-#{SecureRandom.hex(4)}"
    )
    @physical.update!(store_category_id: category.id)

    get store_category_path(category.slug)
    assert_response :success
    refute_includes response.body, @physical.public_id
  end
end

class Commerce::StoreFeaturesCategoryCountTest < ActiveSupport::TestCase
  setup do
    disable_store_features!
    @category = Commerce::Category.create!(name: "Count", slug: "count-#{SecureRandom.hex(4)}")
    Commerce::Product.create!(
      name: "Virtual",
      slug: "virt-#{SecureRandom.hex(4)}",
      store_category_id: @category.id,
      product_type: "virtual",
      status: "active",
      price_cents: 100,
      currency: "CNY"
    )
    Commerce::Product.create!(
      name: "Physical",
      slug: "phys-#{SecureRandom.hex(4)}",
      store_category_id: @category.id,
      product_type: "physical",
      status: "active",
      price_cents: 200,
      currency: "CNY"
    )
    @helper = Class.new do
      include InertiaSerializable
      include Rails.application.routes.url_helpers
    end.new
  end

  test "serialize_category product_count excludes hidden physical products" do
    props = @helper.send(:serialize_category, @category)
    assert_equal 1, props[:product_count]
  end
end

class Commerce::StoreFeaturesAdminProductTest < ActionDispatch::IntegrationTest
  setup do
    disable_store_features!
    @admin = create_user
    grant_permission(@admin, "admin.access")
    grant_permission(@admin, "store.products.manage")
    sign_in_as(@admin)
  end

  test "admin product create strips requires_shipping when shipping disabled" do
    assert_difference -> { Commerce::Product.count }, 1 do
      post admin_store_products_path, params: {
        product: {
          name: "Virtual Ship",
          slug: "virt-ship-#{SecureRandom.hex(4)}",
          product_type: "virtual",
          status: "active",
          price_cents: 500,
          currency: "CNY",
          requires_shipping: true,
          fulfillment_config: "{}"
        }
      }
    end

    product = Commerce::Product.order(:id).last
    assert_not product.requires_shipping?
  end
end
