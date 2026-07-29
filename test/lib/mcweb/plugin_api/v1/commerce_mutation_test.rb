# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/registry"

class Mcweb::PluginApi::V1::CommerceMutationTest < ActiveSupport::TestCase
  setup do
    @staff = create_user(account_type: "staff")
    @buyer = create_user(email: "commerce-mutation-buyer@example.com")
    %w[
      store.orders.read
      store.orders.cancel
      store.orders.mark_paid
      store.orders.mark_fulfilled
      store.inventory.read
      store.inventory.adjust
      store.fulfillments.read
      store.fulfillments.retry
      store.fulfillments.cancel
    ].each { |permission| grant_permission(@staff, permission) }

    @cancel_order = create_order(user: @buyer, status: "pending", total_cents: 1_000)
    @product = Commerce::Product.create!(
      name: "Plugin inventory",
      slug: "plugin-inventory-#{SecureRandom.hex(4)}",
      product_type: "digital",
      status: "active",
      price_cents: 1_000,
      currency: "CNY",
      stock: 10
    )

    @fulfillment_order = create_order(
      user: @buyer,
      status: "fulfilling",
      total_cents: 1_500
    )
    @fulfillment_item = Commerce::OrderItem.create!(
      order: @fulfillment_order,
      product: @product,
      product_name: @product.name,
      unit_price_cents: 1_500,
      quantity: 1,
      total_cents: 1_500
    )
    @fulfillment = Commerce::Fulfillment.create!(
      order: @fulfillment_order,
      order_item: @fulfillment_item,
      status: "failed",
      attempts_count: 1,
      last_error: "private connector failure"
    )

    @refund_order = create_order(user: @buyer, status: "paid", total_cents: 2_000)
    @refund_payment = Payments::Record.create!(
      order: @refund_order,
      provider: "fake",
      provider_payment_id: "payment-#{SecureRandom.hex(6)}",
      status: "succeeded",
      amount_cents: @refund_order.total_cents,
      currency: @refund_order.currency
    )
    SiteSetting.set("store.refund_window_days", "30")
    @reason = "Plugin operator verified the requested state change."
    @api = build_host
  end

  test "signed order cancellation executes once through the core high-risk service" do
    request_uuid = SecureRandom.uuid
    authorization = @api.commerce.authorize_order_action(
      actor: @staff,
      order_public_ids: [ @cancel_order.public_id ],
      action: "cancel_pending",
      request_uuid:,
      reason: @reason
    )

    assert_predicate authorization, :success?
    assert_equal "commerce.action_authorization", authorization.value.fetch("type")
    assert_equal "order.cancel_pending", authorization.value.fetch("operation")
    assert_equal request_uuid, authorization.value.fetch("request_uuid")
    assert_predicate authorization.value, :frozen?
    assert_predicate authorization.value.fetch("targets"), :frozen?

    attributes = {
      actor: @staff,
      order_public_ids: [ @cancel_order.public_id ],
      action: "cancel_pending",
      request_uuid:,
      reason: @reason,
      authorization_token: authorization.value.fetch("authorization_token"),
      confirmation: authorization.value.fetch("confirmation")
    }
    first = @api.commerce.execute_order_action(**attributes)
    replay = @api.commerce.execute_order_action(**attributes)

    assert_predicate first, :success?
    refute first.value.fetch("idempotent")
    assert_predicate replay, :success?
    assert replay.value.fetch("idempotent")
    assert_equal "cancelled", @cancel_order.reload.status
    assert_equal 1, Commerce::HighRiskOperation.where(request_id: request_uuid).count
    assert_equal "commerce.order_action", first.value.fetch("type")
    refute contains_active_record?(first.value)
  end

  test "signed order transitions cover paid and fulfilled core states" do
    paid_request_uuid = SecureRandom.uuid
    paid_authorization = @api.commerce.authorize_order_action(
      actor: @staff,
      order_public_ids: [ @cancel_order.public_id ],
      action: "mark_paid",
      request_uuid: paid_request_uuid,
      reason: @reason
    )
    paid = @api.commerce.execute_order_action(
      actor: @staff,
      order_public_ids: [ @cancel_order.public_id ],
      action: "mark_paid",
      request_uuid: paid_request_uuid,
      reason: @reason,
      authorization_token: paid_authorization.value.fetch("authorization_token"),
      confirmation: paid_authorization.value.fetch("confirmation")
    )

    assert_predicate paid, :success?
    assert_equal "paid", @cancel_order.reload.status

    fulfilled_request_uuid = SecureRandom.uuid
    fulfilled_authorization = @api.commerce.authorize_order_action(
      actor: @staff,
      order_public_ids: [ @cancel_order.public_id ],
      action: "mark_fulfilled",
      request_uuid: fulfilled_request_uuid,
      reason: @reason
    )
    fulfilled = @api.commerce.execute_order_action(
      actor: @staff,
      order_public_ids: [ @cancel_order.public_id ],
      action: "mark_fulfilled",
      request_uuid: fulfilled_request_uuid,
      reason: @reason,
      authorization_token: fulfilled_authorization.value.fetch("authorization_token"),
      confirmation: fulfilled_authorization.value.fetch("confirmation")
    )

    assert_predicate fulfilled, :success?
    assert_equal "fulfilled", @cancel_order.reload.status
    assert_equal %w[order.mark_fulfilled order.mark_paid],
      Commerce::HighRiskOperation
        .where(request_id: [ paid_request_uuid, fulfilled_request_uuid ])
        .order(:action)
        .pluck(:action)
  end

  test "order action permission and signed-state failures use stable public codes" do
    denied = @api.commerce.authorize_order_action(
      actor: @buyer,
      order_public_ids: [ @cancel_order.public_id ],
      action: "cancel_pending",
      request_uuid: SecureRandom.uuid,
      reason: @reason
    )
    assert_equal "forbidden", denied.code
    assert_equal "commerce access denied", denied.error

    request_uuid = SecureRandom.uuid
    authorization = @api.commerce.authorize_order_action(
      actor: @staff,
      order_public_ids: [ @cancel_order.public_id ],
      action: "cancel_pending",
      request_uuid:,
      reason: @reason
    )
    @cancel_order.update!(updated_at: 1.minute.from_now)
    invalid = @api.commerce.execute_order_action(
      actor: @staff,
      order_public_ids: [ @cancel_order.public_id ],
      action: "cancel_pending",
      request_uuid:,
      reason: @reason,
      authorization_token: authorization.value.fetch("authorization_token"),
      confirmation: authorization.value.fetch("confirmation")
    )

    assert_equal "high_risk_authorization_invalid", invalid.code
    assert_equal "commerce operation was rejected", invalid.error
    refute_includes invalid.error, "token"
    assert_equal "pending", @cancel_order.reload.status
  end

  test "inventory adjustment uses signed core service and returns no mutable model" do
    request_uuid = SecureRandom.uuid
    authorization = @api.commerce.authorize_inventory_adjustment(
      actor: @staff,
      target_type: "product",
      target_id: @product.public_id,
      delta: -2,
      request_uuid:,
      reason: @reason
    )
    assert_predicate authorization, :success?

    attributes = {
      actor: @staff,
      target_type: "product",
      target_id: @product.public_id,
      delta: -2,
      request_uuid:,
      reason: @reason,
      authorization_token: authorization.value.fetch("authorization_token"),
      confirmation: authorization.value.fetch("confirmation")
    }
    first = @api.commerce.adjust_inventory(**attributes)
    replay = @api.commerce.adjust_inventory(**attributes)

    assert_predicate first, :success?
    assert_equal 8, first.value.fetch("balance")
    assert_equal(-2, first.value.fetch("delta"))
    refute first.value.fetch("idempotent")
    assert replay.value.fetch("idempotent")
    assert_equal 8, @product.reload.stock
    assert_equal 1, Commerce::InventoryMovement.where(request_id: request_uuid).count
    assert_predicate first.value, :frozen?
    refute contains_active_record?(first.value)
  end

  test "manual fulfillment retry is confirmed idempotent and enqueued after commit" do
    request_uuid = SecureRandom.uuid
    authorization = @api.commerce.authorize_fulfillment_action(
      actor: @staff,
      delivery_id: @fulfillment.delivery_id,
      action: "retry",
      request_uuid:,
      reason: @reason
    )
    assert_predicate authorization, :success?

    attributes = {
      actor: @staff,
      delivery_id: @fulfillment.delivery_id,
      action: "retry",
      request_uuid:,
      reason: @reason,
      authorization_token: authorization.value.fetch("authorization_token"),
      confirmation: authorization.value.fetch("confirmation")
    }
    first = nil
    assert_enqueued_jobs 1, only: Minecraft::EnsureInstanceRunningJob do
      first = @api.commerce.execute_fulfillment_action(**attributes)
    end
    replay = @api.commerce.execute_fulfillment_action(**attributes)

    assert_predicate first, :success?
    refute first.value.fetch("idempotent")
    assert_predicate replay, :success?
    assert replay.value.fetch("idempotent")
    assert_equal "pending", @fulfillment.reload.status
    assert_equal 1, @fulfillment.attempts.where(request_id: request_uuid).count
    refute_includes first.value.to_s, "private connector failure"
    refute contains_active_record?(first.value)
  end

  test "manual fulfillment cancellation uses the dedicated permission and core ledger" do
    request_uuid = SecureRandom.uuid
    authorization = @api.commerce.authorize_fulfillment_action(
      actor: @staff,
      delivery_id: @fulfillment.delivery_id,
      action: "cancel",
      request_uuid:,
      reason: @reason
    )
    result = @api.commerce.execute_fulfillment_action(
      actor: @staff,
      delivery_id: @fulfillment.delivery_id,
      action: "cancel",
      request_uuid:,
      reason: @reason,
      authorization_token: authorization.value.fetch("authorization_token"),
      confirmation: authorization.value.fetch("confirmation")
    )

    assert_predicate result, :success?
    assert_equal "cancelled", @fulfillment.reload.status
    assert_equal @reason, @fulfillment.cancel_reason
    assert_equal 1, @fulfillment.attempts.where(request_id: request_uuid).count
    refute_includes result.value.to_s, @reason
  end

  test "customer refund request is plugin-scoped idempotent and rejects conflicting reuse" do
    request_uuid = SecureRandom.uuid
    first = nil
    replay = nil
    assert_enqueued_jobs 1, only: MailDeliveryJob do
      first = @api.commerce.request_refund(
        actor: @buyer,
        order_public_id: @refund_order.public_id,
        amount_cents: 500,
        reason: @reason,
        request_uuid:
      )
      replay = @api.commerce.request_refund(
        actor: @buyer,
        order_public_id: @refund_order.public_id,
        amount_cents: 500,
        reason: @reason,
        request_uuid:
      )
    end

    assert_predicate first, :success?
    refute first.value.fetch("idempotent")
    assert_predicate replay, :success?
    assert replay.value.fetch("idempotent")
    assert_equal first.value.dig("refund", "id"), replay.value.dig("refund", "id")
    assert_equal 1, @refund_order.refunds.count
    event = @refund_order.events.find_by!(event_type: "refund_requested")
    assert_equal "acme/commerce-mutations", event.metadata.fetch("plugin_id")
    assert_equal request_uuid, event.metadata.fetch("plugin_request_uuid")

    conflict = @api.commerce.request_refund(
      actor: @buyer,
      order_public_id: @refund_order.public_id,
      amount_cents: 600,
      reason: @reason,
      request_uuid:
    )
    assert_equal "idempotency_conflict", conflict.code
    assert_equal 1, @refund_order.refunds.count
  end

  test "refund side effects are discarded when the outer API transaction rolls back" do
    original = Commerce::RequestRefund.method(:call)
    result = nil

    assert_no_enqueued_jobs(only: MailDeliveryJob) do
      Commerce::RequestRefund.stub(
        :call,
        lambda do |**arguments|
          original.call(**arguments).tap do |service_result|
            raise ActiveRecord::StatementInvalid, "database password=private" if service_result.success?
          end
        end
      ) do
        result = @api.commerce.request_refund(
          actor: @buyer,
          order_public_id: @refund_order.public_id,
          amount_cents: 500,
          reason: @reason,
          request_uuid: SecureRandom.uuid
        )
      end
    end

    assert_equal "host_error", result.code
    refute_includes result.error, "password"
    assert_empty @refund_order.refunds.reload
    refute @refund_order.events.where(event_type: "refund_requested").exists?
  end

  test "mutation inputs require persisted actors reason UUID and bounded identifiers" do
    invalid = [
      @api.commerce.authorize_order_action(
        actor: User.new,
        order_public_ids: [ @cancel_order.public_id ],
        action: "cancel_pending",
        request_uuid: SecureRandom.uuid,
        reason: @reason
      ),
      @api.commerce.request_refund(
        actor: @buyer,
        order_public_id: @refund_order.public_id,
        amount_cents: 0,
        reason: @reason,
        request_uuid: SecureRandom.uuid
      ),
      @api.commerce.request_refund(
        actor: @buyer,
        order_public_id: @refund_order.public_id,
        amount_cents: 500,
        reason: "",
        request_uuid: SecureRandom.uuid
      ),
      @api.commerce.request_refund(
        actor: @buyer,
        order_public_id: @refund_order.public_id,
        amount_cents: 500,
        reason: @reason,
        request_uuid: "not-a-uuid"
      )
    ]

    assert_equal "invalid_actor", invalid.first.code
    invalid.drop(1).each do |result|
      assert_equal "invalid_argument", result.code
      assert_predicate result, :frozen?
    end
  end

  test "every mutation entry audits its versioned capability before validation" do
    audits = []
    api = build_host(capability_auditor: ->(capability) { audits << capability })

    api.commerce.authorize_order_action(
      actor: nil,
      order_public_ids: [],
      action: "cancel_pending",
      request_uuid: "invalid",
      reason: ""
    )
    api.commerce.execute_order_action(
      actor: nil,
      order_public_ids: [],
      action: "cancel_pending",
      request_uuid: "invalid",
      reason: "",
      authorization_token: "",
      confirmation: ""
    )
    api.commerce.authorize_inventory_adjustment(
      actor: nil,
      target_type: "product",
      target_id: "",
      delta: 0,
      request_uuid: "invalid",
      reason: ""
    )
    api.commerce.adjust_inventory(
      actor: nil,
      target_type: "product",
      target_id: "",
      delta: 0,
      request_uuid: "invalid",
      reason: "",
      authorization_token: "",
      confirmation: ""
    )
    api.commerce.authorize_fulfillment_action(
      actor: nil,
      delivery_id: "",
      action: "retry",
      request_uuid: "invalid",
      reason: ""
    )
    api.commerce.execute_fulfillment_action(
      actor: nil,
      delivery_id: "",
      action: "retry",
      request_uuid: "invalid",
      reason: "",
      authorization_token: "",
      confirmation: ""
    )
    api.commerce.request_refund(
      actor: nil,
      order_public_id: "",
      amount_cents: 0,
      reason: "",
      request_uuid: "invalid"
    )

    assert_equal(
      {
        "commerce.orders.write" => 2,
        "commerce.inventory.write" => 2,
        "commerce.fulfillments.write" => 2,
        "commerce.refunds.write" => 1
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
      id: "acme/commerce-mutations",
      name: "Commerce Mutations",
      version: "1.0.0",
      api_version: "1",
      capabilities: %w[
        commerce.fulfillments.write
        commerce.inventory.write
        commerce.orders.write
        commerce.refunds.write
      ]
    })
  end

  def create_order(user:, status:, total_cents:)
    Commerce::Order.create!(
      user:,
      status:,
      subtotal_cents: total_cents,
      discount_cents: 0,
      total_cents:,
      currency: "CNY"
    )
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
