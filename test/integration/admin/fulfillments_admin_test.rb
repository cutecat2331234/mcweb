# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  class FulfillmentsAdminTest < ActionDispatch::IntegrationTest
    setup do
      @owner = create_user(account_type: "owner")
      customer = create_user
      order = Commerce::Order.create!(
        user: customer,
        status: "fulfilling",
        currency: "CNY",
        subtotal_cents: 1_000,
        total_cents: 1_000
      )
      item = Commerce::OrderItem.create!(
        order: order,
        product_name: "Admin recovery item",
        unit_price_cents: 1_000,
        quantity: 1,
        total_cents: 1_000,
        fulfillment_snapshot: {}
      )
      @fulfillment = Commerce::Fulfillment.create!(
        order: order,
        order_item: item,
        status: "failed",
        attempts_count: 1,
        last_error: "server_not_found"
      )
      sign_in_as(@owner)
    end

    test "recovery queue and details expose localized state and timeline data" do
      get admin_store_fulfillments_path
      assert_response :success
      assert_equal "Admin/Store/Fulfillments/Index", inertia.component
      props = inertia.props.deep_symbolize_keys
      row = props.fetch(:rows).find { |entry| entry[:id] == @fulfillment.id }
      assert_equal I18n.t("mcweb.labels.fulfillment_status.failed"), row.fetch(:status_label)
      refute_equal "server_not_found", row.fetch(:error_label)

      get admin_store_fulfillment_path(@fulfillment)
      assert_response :success
      assert_equal "Admin/Store/Fulfillments/Show", inertia.component
      props = inertia.props.deep_symbolize_keys
      assert props.dig(:permissions, :retry)
      assert_equal authorize_action_admin_store_fulfillment_path(@fulfillment), props.dig(:paths, :authorize)
    end

    test "JSON authorization and execution retry without remounting the page" do
      request_id = SecureRandom.uuid
      base = {
        fulfillment_action: { action: "retry" },
        request_id: request_id,
        reason: "Verified the payment and delivery target."
      }

      post authorize_action_admin_store_fulfillment_path(@fulfillment), params: base, as: :json
      assert_response :success
      authorization = response.parsed_body
      assert authorization.fetch("preview_items").any?

      post execute_action_admin_store_fulfillment_path(@fulfillment),
           params: base.merge(
             authorization_token: authorization.fetch("authorization_token"),
             confirmation: authorization.fetch("confirmation")
           ),
           as: :json

      assert_response :success
      assert_equal "pending", response.parsed_body.fetch("status")
      assert_equal "private, no-store", response.headers["Cache-Control"]
      assert_equal "pending", @fulfillment.reload.status
    end
  end
end
