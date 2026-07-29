# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  class InventoryAdminTest < ActionDispatch::IntegrationTest
    setup do
      @owner = create_user(account_type: "owner")
      @product = Commerce::Product.create!(
        name: "Admin inventory",
        slug: "admin-inventory-#{SecureRandom.hex(4)}",
        product_type: "digital",
        status: "active",
        price_cents: 500,
        currency: "CNY",
        stock: 4
      )
      sign_in_as(@owner)
    end

    test "inventory page exposes server-calculated balances and capability flags" do
      get admin_store_inventory_path

      assert_response :success
      assert_equal "Admin/Store/Inventory/Index", inertia.component
      props = inertia.props.deep_symbolize_keys
      row = props.fetch(:targets).find { |target| target[:target_id] == @product.public_id }
      assert_equal 4, row.fetch(:available)
      assert props.dig(:permissions, :adjust)
      assert_equal admin_store_inventory_authorize_adjustment_path, props.dig(:paths, :authorize)
    end

    test "authorized adjustment uses JSON preview and execution without page reload" do
      request_id = SecureRandom.uuid
      reason = "Physical stock count correction."
      base = {
        target_type: "product",
        target_id: @product.public_id,
        delta: 2,
        request_id:,
        reason:
      }

      post admin_store_inventory_authorize_adjustment_path,
           params: { adjustment: base },
           as: :json

      assert_response :success
      authorization = response.parsed_body
      assert_equal 6, authorization.dig("preview", "after")

      post admin_store_inventory_adjust_path,
           params: {
             adjustment: base.merge(
               authorization_token: authorization.fetch("authorization_token"),
               confirmation: authorization.fetch("confirmation")
             )
           },
           as: :json

      assert_response :success
      assert_equal 6, response.parsed_body.fetch("balance")
      assert_equal "private, no-store", response.headers["Cache-Control"]
      assert_equal 6, @product.reload.stock
    end
  end
end
