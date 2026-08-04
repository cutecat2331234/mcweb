# frozen_string_literal: true

require "test_helper"

class CommerceProductFiltersTest < ActionDispatch::IntegrationTest
  setup do
    @product = Commerce::Product.create!(
      public_id: "prod_#{SecureRandom.alphanumeric(16)}",
      name: "Searchable product",
      slug: "searchable-#{SecureRandom.hex(4)}",
      price_cents: 1_500,
      currency: "CNY",
      status: "active",
      product_type: "digital"
    )
    @product.variants.create!(name: "Standard", sku: "SEARCH-SKU", price_cents: 1_500)
  end

  test "keyword and price filters qualify product price columns" do
    get store_products_path, params: {
      q: "SEARCH-SKU",
      price_min: "10",
      price_max: "20",
      sort: "price_asc"
    }

    assert_response :success
    assert_includes response.body, @product.name
  end

  test "malformed price filters are ignored without raising" do
    get store_products_path, params: { price_min: "not-a-price", price_max: "Infinity" }

    assert_response :success
    assert_includes response.body, @product.name
  end
end
