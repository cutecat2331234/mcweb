# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/registry"

class Mcweb::PluginApi::V1::CommerceCatalogTest < ActiveSupport::TestCase
  setup do
    @customer = create_user(email: "catalog-customer@example.com")
    @other_customer = create_user
    @catalog_staff = create_user
    @inventory_staff = create_user
    @fulfillment_staff = create_user
    grant_permission(@catalog_staff, "store.products.read")
    grant_permission(@inventory_staff, "store.inventory.read")
    grant_permission(@fulfillment_staff, "store.fulfillments.read")

    @visible_category = Commerce::Category.create!(
      name: "Public goods",
      slug: "public-goods-#{SecureRandom.hex(4)}",
      position: 1
    )
    @draft_category = Commerce::Category.create!(
      name: "Draft goods",
      slug: "draft-goods-#{SecureRandom.hex(4)}",
      position: 2
    )
    @product = Commerce::Product.create!(
      category: @visible_category,
      name: "Public product",
      slug: "public-product-#{SecureRandom.hex(4)}",
      summary: "A public summary",
      description: "Public description",
      product_type: "digital",
      status: "active",
      price_cents: 1_200,
      compare_at_price_cents: 1_500,
      currency: "CNY",
      stock: 8,
      metadata: { "private_supplier" => "secret" },
      fulfillment_config: { "secret_command" => "do not expose" }
    )
    @variant = @product.variants.create!(
      name: "Premium",
      sku: "CATALOG-#{SecureRandom.hex(4)}",
      price_cents: 1_800,
      compare_at_price_cents: 2_000,
      stock: 3,
      fulfillment_config: { "secret_command" => "variant secret" }
    )
    @draft_product = Commerce::Product.create!(
      category: @draft_category,
      name: "Draft product",
      slug: "draft-product-#{SecureRandom.hex(4)}",
      product_type: "digital",
      status: "draft",
      price_cents: 2_500,
      currency: "CNY",
      stock: 2
    )

    @order = Commerce::Order.create!(
      user: @customer,
      status: "fulfilling",
      currency: "CNY",
      subtotal_cents: 1_200,
      total_cents: 1_200
    )
    @item = Commerce::OrderItem.create!(
      order: @order,
      product: @product,
      variant: @variant,
      product_name: @product.name,
      variant_name: @variant.name,
      unit_price_cents: 1_200,
      quantity: 1,
      total_cents: 1_200
    )
    @fulfillment = Commerce::Fulfillment.create!(
      order: @order,
      order_item: @item,
      status: "failed",
      attempts_count: 1,
      last_error: "connector-password=private"
    )
    @api = build_host
  end

  test "customer catalog exposes only available products and immutable allow-listed DTOs" do
    categories = @api.commerce.categories(user: @customer)
    products = @api.commerce.products(user: @customer)
    product = @api.commerce.find_product(
      user: @customer,
      public_id: @product.public_id
    )

    assert_predicate categories, :success?
    assert_equal [ @visible_category.id ], categories.value.pluck("id")
    assert_predicate products, :success?
    assert_equal [ @product.public_id ], products.value.pluck("public_id")
    assert_predicate product, :success?
    assert_predicate product.value, :frozen?
    assert_predicate product.value.fetch("variants"), :frozen?
    assert_equal "commerce.product", product.value.fetch("type")
    assert_equal 1_200, product.value.fetch("price_cents")
    assert_equal @variant.sku, product.value.dig("variants", 0, "sku")
    assert product.value.dig("availability", "purchasable")
    refute contains_active_record?(product.value)

    serialized = product.value.to_s
    refute_includes serialized, "private_supplier"
    refute_includes serialized, "secret_command"
    refute_includes serialized, "connector-password"
    assert_raises(FrozenError) { product.value["name"] = "mutated" }

    hidden = @api.commerce.find_product(
      user: @customer,
      public_id: @draft_product.public_id
    )
    assert_equal "not_found", hidden.code
  end

  test "catalog staff can inspect draft pricing while customer availability stays public" do
    products = @api.commerce.products(
      user: @catalog_staff,
      available: false
    )
    pricing = @api.commerce.prices(
      user: @catalog_staff,
      slug: @draft_product.slug
    )
    availability = @api.commerce.availability(
      user: @customer,
      slug: @product.slug
    )

    assert_equal [ @draft_product.public_id ], products.value.pluck("public_id")
    assert_predicate pricing, :success?
    assert_equal "commerce.pricing", pricing.value.fetch("type")
    assert_equal @draft_product.price_cents, pricing.value.fetch("price_cents")
    refute_includes pricing.value.keys, "stock"

    assert_predicate availability, :success?
    assert_equal "commerce.availability", availability.value.fetch("type")
    assert availability.value.fetch("available")
    assert availability.value.fetch("in_stock")
    assert availability.value.fetch("purchasable")
    refute_includes availability.value.keys, "available_quantity"
  end

  test "inventory requires the canonical permission and reports bounded target snapshots" do
    denied = @api.commerce.inventory(user: @customer)
    result = @api.commerce.inventory(
      user: @inventory_staff,
      product_public_id: @product.public_id,
      limit: 2
    )
    found = @api.commerce.find_inventory(
      user: @inventory_staff,
      target_type: "variant",
      target_id: @variant.id
    )

    assert_equal "forbidden", denied.code
    assert_predicate result, :success?
    assert_equal 2, result.value.length
    assert_equal %w[product variant], result.value.pluck("target_type")
    assert_predicate found, :success?
    assert_equal "commerce.inventory", found.value.fetch("type")
    assert_equal 3, found.value.fetch("available_quantity")
    assert_equal 0, found.value.fetch("reserved_quantity")
    assert_predicate found.value, :frozen?
    refute contains_active_record?(result.value)
  end

  test "fulfillment reads are order scoped and omit operational errors" do
    own = @api.commerce.fulfillments(
      user: @customer,
      order_public_id: @order.public_id
    )
    found = @api.commerce.find_fulfillment(
      user: @customer,
      delivery_id: @fulfillment.delivery_id
    )
    hidden = @api.commerce.find_fulfillment(
      user: @other_customer,
      delivery_id: @fulfillment.delivery_id
    )
    staff = @api.commerce.find_fulfillment(
      user: @fulfillment_staff,
      delivery_id: @fulfillment.delivery_id
    )
    unrelated_staff = @api.commerce.find_fulfillment(
      user: @catalog_staff,
      delivery_id: @fulfillment.delivery_id
    )

    assert_predicate own, :success?
    assert_equal [ @fulfillment.delivery_id ], own.value.pluck("delivery_id")
    assert_predicate found, :success?
    assert_equal "commerce.fulfillment_status", found.value.fetch("type")
    refute_includes found.value.keys, "last_error"
    refute_includes found.value.to_s, "connector-password"
    assert_equal "not_found", hidden.code
    assert_predicate staff, :success?
    assert_equal "not_found", unrelated_staff.code
  end

  test "invalid catalog and inventory inputs have stable failures" do
    results = [
      @api.commerce.products(user: @customer, available: "yes"),
      @api.commerce.find_product(user: @customer),
      @api.commerce.find_product(
        user: @customer,
        public_id: @product.public_id,
        slug: @product.slug
      ),
      @api.commerce.inventory(user: @inventory_staff, target_type: "warehouse"),
      @api.commerce.find_inventory(
        user: @inventory_staff,
        target_type: "variant",
        target_id: 0
      ),
      @api.commerce.find_fulfillment(user: @customer)
    ]

    results.each do |result|
      assert_predicate result, :failure?
      assert_equal "invalid_argument", result.code
      assert_predicate result, :frozen?
    end
  end

  test "every catalog inventory and fulfillment operation audits its versioned capability" do
    audits = []
    api = build_host(capability_auditor: ->(capability) { audits << capability })

    api.commerce.categories(user: @customer)
    api.commerce.products(user: @customer)
    api.commerce.find_product(user: @customer, public_id: @product.public_id)
    api.commerce.prices(user: @customer, public_id: @product.public_id)
    api.commerce.availability(user: @customer, public_id: @product.public_id)
    api.commerce.inventory(user: @inventory_staff, limit: 1)
    api.commerce.find_inventory(
      user: @inventory_staff,
      target_type: "product",
      target_id: @product.public_id
    )
    api.commerce.fulfillments(
      user: @customer,
      order_public_id: @order.public_id
    )
    api.commerce.find_fulfillment(
      user: @customer,
      delivery_id: @fulfillment.delivery_id
    )

    assert_equal(
      {
        "commerce.catalog.read" => 5,
        "commerce.inventory.read" => 2,
        "commerce.fulfillments.read" => 2
      },
      audits.tally
    )
  end

  private

  def build_host(capability_auditor: nil)
    Mcweb::PluginApi::V1::Host.new(
      manifest: manifest,
      event_bus: Mcweb::Events,
      capability_auditor:
    )
  end

  def manifest
    Mcweb::Plugins::Manifest.from_hash({
      id: "acme/commerce-catalog",
      name: "Commerce Catalog",
      version: "1.0.0",
      api_version: "1",
      capabilities: %w[
        commerce.catalog.read
        commerce.fulfillments.read
        commerce.inventory.read
      ]
    })
  end

  def contains_active_record?(value)
    case value
    when ActiveRecord::Base
      true
    when Hash
      value.any? { |key, item| contains_active_record?(key) || contains_active_record?(item) }
    when Array
      value.any? { |item| contains_active_record?(item) }
    else
      false
    end
  end
end
