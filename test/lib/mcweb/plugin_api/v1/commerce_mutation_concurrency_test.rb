# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/registry"

class Mcweb::PluginApi::V1::CommerceMutationConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @staff = create_user(account_type: "staff")
    @buyer = create_user
    grant_permission(@staff, "store.orders.cancel")

    @cancel_order = create_order(user: @buyer, status: "pending", total_cents: 1_000)
    @refund_order = create_order(user: @buyer, status: "paid", total_cents: 2_000)
    @payment = Payments::Record.create!(
      order: @refund_order,
      provider: "fake",
      provider_payment_id: "plugin-concurrency-#{SecureRandom.hex(5)}",
      status: "succeeded",
      amount_cents: @refund_order.total_cents,
      currency: @refund_order.currency
    )
    SiteSetting.set("store.refund_window_days", "30")
    @api = build_host
  end

  teardown do
    order_ids = [ @cancel_order.id, @refund_order.id ]
    user_ids = [ @staff.id, @buyer.id ]
    AuditLog.where(actor_id: user_ids).delete_all
    Commerce::HighRiskOperation.where(actor_id: user_ids).delete_all
    Commerce::OrderEvent.where(store_order_id: order_ids).delete_all
    Commerce::Refund.where(store_order_id: order_ids).delete_all
    Payments::Record.where(store_order_id: order_ids).delete_all
    Notification.where(user_id: user_ids).delete_all
    Commerce::Order.where(id: order_ids).delete_all
    Community::GroupMembership.where(user_id: user_ids).delete_all
    UserRole.where(user_id: user_ids).delete_all
    User.where(id: user_ids).delete_all
  end

  test "concurrent signed order submissions commit one core operation" do
    request_uuid = SecureRandom.uuid
    reason = "Concurrent plugin order action"
    authorization = @api.commerce.authorize_order_action(
      actor: @staff,
      order_public_ids: [ @cancel_order.public_id ],
      action: "cancel_pending",
      request_uuid:,
      reason:
    )
    assert_predicate authorization, :success?

    responses = concurrently(2) do
      @api.commerce.execute_order_action(
        actor: User.find(@staff.id),
        order_public_ids: [ @cancel_order.public_id ],
        action: "cancel_pending",
        request_uuid:,
        reason:,
        authorization_token: authorization.value.fetch("authorization_token"),
        confirmation: authorization.value.fetch("confirmation")
      )
    end

    assert responses.all?(&:success?), responses.map(&:to_h).inspect
    assert_equal 1, responses.count { |result| result.value.fetch("idempotent") }
    assert_equal 1, responses.count { |result| !result.value.fetch("idempotent") }
    assert_equal "cancelled", @cancel_order.reload.status
    assert_equal 1, Commerce::HighRiskOperation.where(request_id: request_uuid).count
  end

  test "concurrent refund requests serialize on the actor and create one refund" do
    request_uuid = SecureRandom.uuid
    reason = "Concurrent customer refund request"

    responses = concurrently(2) do
      @api.commerce.request_refund(
        actor: User.find(@buyer.id),
        order_public_id: @refund_order.public_id,
        amount_cents: 500,
        reason:,
        request_uuid:
      )
    end

    assert responses.all?(&:success?), responses.map(&:to_h).inspect
    assert_equal 1, responses.count { |result| result.value.fetch("idempotent") }
    assert_equal 1, responses.count { |result| !result.value.fetch("idempotent") }
    assert_equal 1, Commerce::Refund.where(store_order_id: @refund_order.id).count
    assert_equal 1,
      Commerce::OrderEvent
        .where(store_order_id: @refund_order.id, event_type: "refund_requested")
        .count
  end

  private

  def concurrently(count)
    ready = Queue.new
    gate = Queue.new
    responses = Queue.new
    threads = count.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          gate.pop
          responses << yield
        end
      end
    end

    count.times { ready.pop }
    count.times { gate << true }
    count.times.map { responses.pop }
  ensure
    threads&.each(&:join)
  end

  def build_host
    Mcweb::PluginApi::V1::Host.new(
      manifest: Mcweb::Plugins::Manifest.from_hash({
        id: "acme/commerce-concurrency",
        name: "Commerce Concurrency",
        version: "1.0.0",
        api_version: "1",
        capabilities: %w[
          commerce.orders.write
          commerce.refunds.write
        ]
      }),
      event_bus: Mcweb::Events
    )
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
end
