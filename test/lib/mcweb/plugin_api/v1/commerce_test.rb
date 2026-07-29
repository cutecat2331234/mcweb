# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/registry"

class Mcweb::PluginApi::V1::CommerceTest < ActiveSupport::TestCase
  setup do
    @customer = create_user(email: "commerce-customer@example.com")
    @other_customer = create_user
    @staff = create_user
    @refund_only_staff = create_user
    grant_permission(@staff, "store.orders.read")
    grant_permission(@refund_only_staff, "store.orders.refund")

    @order = create_order(
      user: @customer,
      status: "paid",
      total_cents: 12_345,
      notes: "private buyer note",
      shipping_address: {
        "name" => "Private Customer",
        "phone" => "13800000000",
        "address" => "Private address"
      }
    )
    @other_order = create_order(
      user: @other_customer,
      status: "pending",
      total_cents: 6_789
    )
    @payment = Payments::Record.create!(
      order: @order,
      provider: "stripe",
      provider_payment_id: "pi_private_reference",
      status: "succeeded",
      amount_cents: @order.total_cents,
      currency: @order.currency,
      metadata: {
        "client_secret" => "payment_secret",
        "receipt_email" => @customer.email
      }
    )
    @refund = Commerce::Refund.create!(
      order: @order,
      payment_record: @payment,
      requested_by: @customer,
      status: "completed",
      amount_cents: 2_000,
      reason: "private refund reason",
      requested_by_customer: true
    )
    @api = build_host
  end

  test "customer order reads are owner scoped immutable and minimal" do
    orders = @api.commerce.orders(user: @customer)
    found = @api.commerce.find_order(user: @customer, public_id: @order.public_id)

    assert_predicate orders, :success?
    assert_equal [ @order.id ], orders.value.pluck("id")
    assert_predicate orders.value, :frozen?
    assert_predicate orders.value.first, :frozen?

    assert_predicate found, :success?
    assert_equal(
      %w[created_at currency id public_id schema_version status total_cents type updated_at],
      found.value.keys.sort
    )
    assert_equal "commerce.order_status", found.value.fetch("type")
    assert_equal "paid", found.value.fetch("status")
    assert_equal 12_345, found.value.fetch("total_cents")
    assert_predicate found.value.fetch("currency"), :frozen?
    assert_raises(FrozenError) { found.value["status"] = "refunded" }
    refute contains_active_record?(found.value)

    %w[
      user_id order_number notes shipping_address shipping_method
      tracking_number coupon gift_card
    ].each do |sensitive_key|
      refute_includes found.value.keys, sensitive_key
    end
    refute_includes found.value.to_s, @customer.email
    refute_includes found.value.to_s, "Private Customer"
  end

  test "payment and refund snapshots omit provider identifiers metadata reasons and actors" do
    payments = @api.commerce.payments(
      user: @customer,
      order_public_id: @order.public_id
    )
    payment = @api.commerce.find_payment(user: @customer, id: @payment.id)
    refunds = @api.commerce.refunds(
      user: @customer,
      order_public_id: @order.public_id
    )
    refund = @api.commerce.find_refund(user: @customer, id: @refund.id)

    [ payments, payment, refunds, refund ].each do |result|
      assert_predicate result, :success?
      assert_predicate result.value, :frozen?
      refute contains_active_record?(result.value)
    end

    assert_equal [ @payment.id ], payments.value.pluck("id")
    assert_equal(
      %w[amount_cents created_at currency id order_public_id schema_version status type updated_at],
      payment.value.keys.sort
    )
    assert_equal "commerce.payment_status", payment.value.fetch("type")
    assert_equal "succeeded", payment.value.fetch("status")

    assert_equal [ @refund.id ], refunds.value.pluck("id")
    assert_equal(
      %w[amount_cents created_at currency id order_public_id schema_version status type updated_at],
      refund.value.keys.sort
    )
    assert_equal "commerce.refund_status", refund.value.fetch("type")
    assert_equal "completed", refund.value.fetch("status")

    serialized = [ payments.value, refunds.value ].to_s
    refute_includes serialized, "stripe"
    refute_includes serialized, "pi_private_reference"
    refute_includes serialized, "payment_secret"
    refute_includes serialized, @customer.email
    refute_includes serialized, "private refund reason"
  end

  test "order ownership and canonical staff permission bound every nested and direct read" do
    assert_not_visible @api.commerce.find_order(user: @other_customer, id: @order.id), "order"
    assert_not_visible @api.commerce.payments(user: @other_customer, order_id: @order.id), "order"
    assert_not_visible @api.commerce.find_payment(user: @other_customer, id: @payment.id), "payment"
    assert_not_visible @api.commerce.refunds(user: @other_customer, order_id: @order.id), "order"
    assert_not_visible @api.commerce.find_refund(user: @other_customer, id: @refund.id), "refund"

    staff_orders = @api.commerce.orders(user: @staff)
    assert_includes staff_orders.value.pluck("id"), @order.id
    assert_includes staff_orders.value.pluck("id"), @other_order.id
    assert_predicate @api.commerce.find_order(user: @staff, id: @order.id), :success?
    assert_predicate @api.commerce.find_payment(user: @staff, id: @payment.id), :success?
    assert_predicate @api.commerce.find_refund(user: @staff, id: @refund.id), :success?

    assert_not_visible(
      @api.commerce.find_order(user: @refund_only_staff, id: @order.id),
      "order"
    )
  end

  test "invalid selectors filters actors and account states fail without lookup leakage" do
    invalid_results = [
      @api.commerce.orders(user: nil),
      @api.commerce.orders(user: Object.new),
      @api.commerce.orders(user: @customer, limit: 0),
      @api.commerce.orders(user: @customer, limit: 101),
      @api.commerce.orders(user: @customer, status: "unknown"),
      @api.commerce.find_order(user: @customer),
      @api.commerce.find_order(
        user: @customer,
        id: @order.id,
        public_id: @order.public_id
      ),
      @api.commerce.find_order(user: @customer, id: 0),
      @api.commerce.payments(user: @customer),
      @api.commerce.find_payment(user: @customer, id: "not-an-id"),
      @api.commerce.refunds(user: @customer),
      @api.commerce.find_refund(user: @customer, id: -1)
    ]

    invalid_results.each do |result|
      assert_predicate result, :failure?
      assert_includes %w[invalid_argument invalid_user], result.code
      assert_predicate result, :frozen?
    end

    missing = @api.commerce.find_order(
      user: @other_customer,
      id: Commerce::Order.maximum(:id).to_i + 10_000
    )
    hidden = @api.commerce.find_order(user: @other_customer, id: @order.id)
    assert_equal "not_found", missing.code
    assert_equal missing.error, hidden.error

    @customer.ban!(reason: "private moderation state")
    forbidden = @api.commerce.find_order(user: @customer, id: @order.id)
    assert_equal "forbidden", forbidden.code
    refute_includes forbidden.error, "private moderation state"
  end

  test "capability use is audited and undeclared low-level writes stay unavailable" do
    audits = []
    api = build_host(capability_auditor: ->(capability) { audits << capability })

    api.commerce.orders(user: @customer)
    api.commerce.find_order(user: @customer, id: @order.id)
    api.commerce.payments(user: @customer, order_id: @order.id)
    api.commerce.find_payment(user: @customer, id: @payment.id)
    api.commerce.refunds(user: @customer, order_id: @order.id)
    api.commerce.find_refund(user: @customer, id: @refund.id)

    assert_equal(
      {
        "commerce.orders.read" => 2,
        "commerce.payments.read" => 2,
        "commerce.refunds.read" => 2
      },
      audits.tally
    )
    assert_predicate api.commerce, :frozen?
    assert_predicate api, :frozen?
    assert api.declares_capability?("commerce.orders.read")

    %i[
      create_payment
      process_refund
      transition_order
    ].each do |write_method|
      refute_respond_to api.commerce, write_method
    end
  end

  test "infrastructure failures return a stable error without exception or secret details" do
    @staff.define_singleton_method(:permission?) do |_key|
      raise "database failed with password=private"
    end

    result = @api.commerce.orders(user: @staff)

    assert_predicate result, :failure?
    assert_equal "host_error", result.code
    assert_equal "commerce host operation failed", result.error
    refute_includes result.error, "password"
    assert_predicate result, :frozen?
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
      id: "acme/commerce-api",
      name: "Commerce API",
      version: "1.0.0",
      api_version: "1",
      capabilities: %w[
        commerce.orders.read
        commerce.payments.read
        commerce.refunds.read
      ]
    })
  end

  def create_order(user:, status:, total_cents:, notes: nil, shipping_address: {})
    Commerce::Order.create!(
      user:,
      status:,
      subtotal_cents: total_cents,
      discount_cents: 0,
      total_cents:,
      currency: "CNY",
      notes:,
      shipping_address:
    )
  end

  def assert_not_visible(result, resource)
    assert_predicate result, :failure?
    assert_equal "not_found", result.code
    assert_equal "#{resource} not found or not visible", result.error
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
