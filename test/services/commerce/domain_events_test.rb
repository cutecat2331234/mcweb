# frozen_string_literal: true

require "test_helper"

module Commerce
  class DomainEventsTest < ActiveSupport::TestCase
    test "catalog exposes every stable commerce event" do
      Commerce::DomainEvents::EVENTS.each do |event|
        assert_includes Mcweb::Events::CATALOG, event
      end
    end

    test "publisher waits for the outer commit hook and defers listener delivery" do
      callbacks = []
      delivered = []
      deferred_calls = 0
      subscriber = Mcweb::Events.subscribe("commerce.payment.failed") do |payload|
        delivered << payload
      end
      payload = {
        payment: { id: 7, status: "failed", amount_cents: 500, currency: "CNY" },
        order: { public_id: "order-safe", status: "awaiting_payment", total_cents: 500, currency: "CNY" }
      }

      ActiveRecord.stub(:after_all_transactions_commit, ->(&block) { callbacks << block }) do
        Mcweb::Events.stub(
          :defer_until_success,
          lambda do |&block|
            deferred_calls += 1
            block.call
          end
        ) do
          assert Commerce::DomainEvents.publish_after_commit(
            "commerce.payment.failed",
            payload
          )
          assert_empty delivered
          callbacks.sole.call
        end
      end

      assert_equal 1, deferred_calls
      assert_equal payload, delivered.sole
      assert_predicate delivered.sole, :frozen?
      assert_predicate delivered.sole.fetch(:payment), :frozen?
    ensure
      Mcweb::Events.unsubscribe(subscriber) if subscriber
    end

    test "payment confirmation and terminal failure publish once without private metadata" do
      user = create_user(
        email: "customer-private-sentinel@example.com",
        username: "customer_private_sentinel"
      )
      order = create_order(user:, status: "pending")
      payment = Payments::Record.create!(
        order:,
        provider: "fake",
        provider_payment_id: "provider-private-sentinel",
        status: "pending",
        amount_cents: order.total_cents,
        currency: order.currency,
        metadata: {
          "provider_secret" => "secret-private-sentinel",
          "customer_email" => user.email
        }
      )
      failed_payment = Payments::Record.create!(
        order: create_order(user:, status: "awaiting_payment"),
        provider: "fake",
        provider_payment_id: "failed-private-sentinel",
        status: "pending",
        amount_cents: 1_000,
        currency: "CNY",
        metadata: { "provider_secret" => "failed-secret-private-sentinel" }
      )

      events = capture_events(
        "commerce.payment.confirmed",
        "commerce.payment.failed"
      ) do
        Commerce::CompleteOrderPayment.stub(:call, ServiceResult.success) do
          first = Commerce::ConfirmPayment.call(payment_record: payment)
          replay = Commerce::ConfirmPayment.call(payment_record: payment.reload)
          assert_predicate first, :success?
          assert_predicate replay, :success?
        end
        assert failed_payment.mark_failed!
        refute failed_payment.reload.mark_failed!
      end

      assert_equal 1, events.fetch("commerce.payment.confirmed").length
      assert_equal 1, events.fetch("commerce.payment.failed").length
      serialized = events.to_json
      refute_match(/private-sentinel/i, serialized)
      assert_equal order.public_id,
        events.fetch("commerce.payment.confirmed").sole.dig(:order, :public_id)
    end

    test "staff-marked payment publishes one confirmation and is replay safe" do
      order = create_order(user: create_user, status: "paid")
      order.events.create!(
        event_type: Commerce::PostPaymentSideEffectsJob::COMPLETED_EVENT,
        metadata: {}
      )
      order.events.create!(
        event_type: Commerce::CompleteOrderPayment::FULFILL_ORDER_ENQUEUED_EVENT,
        metadata: {}
      )
      success = ServiceResult.success

      events = capture_events("commerce.payment.confirmed") do
        Commerce::DebitGiftCard.stub(:call, success) do
          Commerce::DebitStoreCredit.stub(:call, success) do
            Commerce::IssueFinanceInvoice.stub(:call, success) do
              first = Commerce::CompleteOrderPayment.call(order:, staff_marked: true)
              replay = Commerce::CompleteOrderPayment.call(
                order: order.reload,
                staff_marked: true
              )
              assert_predicate first, :success?, first.error
              assert_predicate replay, :success?, replay.error
            end
          end
        end
      end

      payload = events.fetch("commerce.payment.confirmed").sole
      assert_equal order.public_id, payload.dig(:order, :public_id)
      assert_equal "succeeded", payload.dig(:payment, :status)
      assert_equal 1, order.payment_records.where(status: "succeeded").count
      refute_match(/staff_marked/, payload.to_json)
    end

    test "inventory transitions publish one allow-listed event per actual movement" do
      user = create_user
      product = Commerce::Product.create!(
        name: "Event inventory",
        slug: "event-inventory-#{SecureRandom.hex(4)}",
        product_type: "digital",
        status: "active",
        price_cents: 1_000,
        currency: "CNY",
        stock: 10
      )
      first_order, first_item = order_and_item(user:, product:, quantity: 2)
      second_order, second_item = order_and_item(user:, product:, quantity: 1)

      events = capture_events(
        "commerce.inventory.reserved",
        "commerce.inventory.confirmed",
        "commerce.inventory.released"
      ) do
        reserve = Commerce::ReserveInventory.call(order_item: first_item)
        assert_predicate reserve, :success?
        replay = Commerce::ReserveInventory.call(order_item: first_item)
        assert_predicate replay, :success?
        assert replay.value.fetch(:replayed)

        confirm = Commerce::ConfirmInventoryReservations.call(order: first_order)
        confirm_replay = Commerce::ConfirmInventoryReservations.call(order: first_order)
        assert_predicate confirm, :success?
        assert_predicate confirm_replay, :success?

        second_reserve = Commerce::ReserveInventory.call(order_item: second_item)
        assert_predicate second_reserve, :success?
        release = Commerce::ReleaseInventoryReservations.call(
          order: second_order,
          reason: "private-release-reason"
        )
        release_replay = Commerce::ReleaseInventoryReservations.call(
          order: second_order,
          reason: "private-release-reason"
        )
        assert_predicate release, :success?
        assert_predicate release_replay, :success?
      end

      assert_equal 2, events.fetch("commerce.inventory.reserved").length
      assert_equal 1, events.fetch("commerce.inventory.confirmed").length
      assert_equal 1, events.fetch("commerce.inventory.released").length
      refute_match(/private-release-reason/, events.to_json)
      movement = events.fetch("commerce.inventory.confirmed").sole.fetch(:movement)
      assert_equal %i[
        available_delta public_id quantity reserved_delta sold_delta type
      ], movement.keys.sort
    end

    test "refund lifecycle publishes request rejection and completed payment events once" do
      user = create_user
      approver = create_user
      enable_refund_window!

      rejected_order = paid_order_with_payment(user:)
      anchor_order_payment_at!(rejected_order)
      processed_order = paid_order_with_payment(user:)
      processed_payment = processed_order.payment_records.sole
      processed_refund = Commerce::Refund.create!(
        order: processed_order,
        payment_record: processed_payment,
        status: "pending",
        amount_cents: processed_order.total_cents,
        requested_by: user,
        reason: "private-refund-reason"
      )

      events = capture_events(
        "commerce.refund.requested",
        "commerce.refund.rejected",
        "commerce.refund.processed",
        "commerce.payment.refunded"
      ) do
        requested = Commerce::RequestRefund.call(
          order: rejected_order,
          user:,
          reason: "private-request-reason"
        )
        assert_predicate requested, :success?, requested.error
        rejected = Commerce::RejectRefund.call(
          refund: requested.value,
          actor: approver,
          reason: "private-rejection-reason"
        )
        assert_predicate rejected, :success?, rejected.error

        processed = Commerce::ProcessRefund.call(
          order: processed_order,
          payment_record: processed_payment,
          amount_cents: processed_refund.amount_cents,
          approved_by: approver,
          existing_refund: processed_refund
        )
        replay = Commerce::ProcessRefund.call(
          order: processed_order.reload,
          payment_record: processed_payment.reload,
          amount_cents: processed_refund.amount_cents,
          approved_by: approver,
          existing_refund: processed_refund.reload
        )
        assert_predicate processed, :success?, processed.error
        assert_predicate replay, :success?, replay.error
      end

      %w[
        commerce.refund.requested
        commerce.refund.rejected
        commerce.refund.processed
        commerce.payment.refunded
      ].each do |event|
        assert_equal 1, events.fetch(event).length
      end
      refute_match(/private-(?:request|rejection|refund)-reason/, events.to_json)
      assert_equal "completed",
        events.fetch("commerce.refund.processed").sole.dig(:refund, :status)
    end

    test "fulfillment attempts publish dispatched retryable terminal and completed events" do
      order = create_order(user: create_user, status: "fulfilling")
      item = Commerce::OrderItem.create!(
        order:,
        product_name: "Event delivery",
        unit_price_cents: 1_000,
        quantity: 1,
        total_cents: 1_000,
        fulfillment_snapshot: {}
      )
      retryable = Commerce::Fulfillment.create!(
        order:,
        order_item: item,
        status: "pending",
        max_attempts: 3
      )
      terminal_item = Commerce::OrderItem.create!(
        order:,
        product_name: "Terminal delivery",
        unit_price_cents: 1_000,
        quantity: 1,
        total_cents: 1_000,
        fulfillment_snapshot: {}
      )
      terminal = Commerce::Fulfillment.create!(
        order:,
        order_item: terminal_item,
        status: "pending",
        max_attempts: 1
      )

      events = capture_events(
        "commerce.fulfillment.dispatched",
        "commerce.fulfillment.retryable_failed",
        "commerce.fulfillment.failed",
        "commerce.fulfillment.completed"
      ) do
        first_attempt = retryable.begin_dispatch_attempt!
        retryable.mark_failed!(
          attempt: first_attempt,
          error: "temporary_provider_failure",
          result: {
            status: "retryable",
            error_code: "temporary_provider_failure",
            provider_secret: "private-provider-secret"
          }
        )
        retryable.mark_failed!(
          attempt: first_attempt,
          error: "temporary_provider_failure",
          result: {
            status: "retryable",
            error_code: "temporary_provider_failure"
          }
        )
        retryable.update!(status: "pending", next_attempt_at: nil)
        second_attempt = retryable.begin_dispatch_attempt!
        retryable.mark_fulfilled!(
          attempt: second_attempt,
          result: {
            status: "completed",
            external_reference: "safe-reference",
            provider_secret: "private-provider-secret"
          }
        )
        retryable.reload.mark_fulfilled!(result: { status: "completed" })

        terminal_attempt = terminal.begin_dispatch_attempt!
        terminal.mark_failed!(
          attempt: terminal_attempt,
          error: "terminal_provider_failure",
          retryable: false
        )
      end

      assert_equal 3, events.fetch("commerce.fulfillment.dispatched").length
      assert_equal 1, events.fetch("commerce.fulfillment.retryable_failed").length
      assert_equal 1, events.fetch("commerce.fulfillment.failed").length
      assert_equal 1, events.fetch("commerce.fulfillment.completed").length
      refute_match(/private-provider-secret/, events.to_json)
      assert_equal "safe-reference",
        events.fetch("commerce.fulfillment.completed").sole.dig(:result, "external_reference")
    end

    test "signed inventory adjustment and cancellation publish only after execution" do
      actor = create_user
      grant_permission(actor, "store.inventory.adjust")
      grant_permission(actor, "store.fulfillments.cancel")
      product = Commerce::Product.create!(
        name: "Signed event inventory",
        slug: "signed-event-inventory-#{SecureRandom.hex(4)}",
        product_type: "digital",
        status: "active",
        price_cents: 1_000,
        currency: "CNY",
        stock: 4
      )
      adjustment_request_id = SecureRandom.uuid
      adjustment_reason = "private-adjustment-reason"
      adjustment_authorization = Commerce::InventoryAdjustment.call(
        actor:,
        target: product,
        delta: 2,
        request_id: adjustment_request_id,
        reason: adjustment_reason,
        authorize_only: true
      )
      assert_predicate adjustment_authorization, :success?

      order = create_order(user: create_user, status: "fulfilling")
      item = Commerce::OrderItem.create!(
        order:,
        product_name: "Cancellable delivery",
        unit_price_cents: 1_000,
        quantity: 1,
        total_cents: 1_000,
        fulfillment_snapshot: {}
      )
      fulfillment = Commerce::Fulfillment.create!(
        order:,
        order_item: item,
        status: "failed",
        attempts_count: 1,
        last_error: "temporary"
      )
      cancellation_request_id = SecureRandom.uuid
      cancellation_reason = "private-cancellation-reason"
      cancellation_authorization = Commerce::ManualFulfillmentAction.call(
        actor:,
        fulfillment:,
        action: "cancel",
        request_id: cancellation_request_id,
        reason: cancellation_reason,
        authorize_only: true
      )
      assert_predicate cancellation_authorization, :success?

      events = capture_events(
        "commerce.inventory.adjusted",
        "commerce.fulfillment.cancelled"
      ) do
        adjusted = Commerce::InventoryAdjustment.call(
          actor:,
          target: product,
          delta: 2,
          request_id: adjustment_request_id,
          reason: adjustment_reason,
          authorization_token: adjustment_authorization.value.fetch(:authorization_token),
          confirmation: adjustment_authorization.value.fetch(:confirmation)
        )
        adjusted_replay = Commerce::InventoryAdjustment.call(
          actor:,
          target: product,
          delta: 2,
          request_id: adjustment_request_id,
          reason: adjustment_reason,
          authorization_token: adjustment_authorization.value.fetch(:authorization_token),
          confirmation: adjustment_authorization.value.fetch(:confirmation)
        )
        cancelled = Commerce::ManualFulfillmentAction.call(
          actor:,
          fulfillment:,
          action: "cancel",
          request_id: cancellation_request_id,
          reason: cancellation_reason,
          authorization_token: cancellation_authorization.value.fetch(:authorization_token),
          confirmation: cancellation_authorization.value.fetch(:confirmation)
        )
        cancelled_replay = Commerce::ManualFulfillmentAction.call(
          actor:,
          fulfillment:,
          action: "cancel",
          request_id: cancellation_request_id,
          reason: cancellation_reason,
          authorization_token: cancellation_authorization.value.fetch(:authorization_token),
          confirmation: cancellation_authorization.value.fetch(:confirmation)
        )
        assert_predicate adjusted, :success?, adjusted.error
        assert_predicate adjusted_replay, :success?, adjusted_replay.error
        assert adjusted_replay.value.fetch(:idempotent)
        assert_predicate cancelled, :success?, cancelled.error
        assert_predicate cancelled_replay, :success?, cancelled_replay.error
        assert cancelled_replay.value.fetch(:idempotent)
      end

      assert_equal 1, events.fetch("commerce.inventory.adjusted").length
      assert_equal 1, events.fetch("commerce.fulfillment.cancelled").length
      refute_match(/private-(?:adjustment|cancellation)-reason/, events.to_json)
    end

    private

    def capture_events(*names)
      callbacks = []
      events = names.index_with { [] }
      subscriptions = names.map do |name|
        Mcweb::Events.subscribe(name) { |payload| events.fetch(name) << payload }
      end

      ActiveRecord.stub(:after_all_transactions_commit, ->(&block) { callbacks << block }) do
        yield
      end
      callbacks.each(&:call)
      events
    ensure
      Array(subscriptions).each { |subscriber| Mcweb::Events.unsubscribe(subscriber) }
    end

    def create_order(user:, status:, total_cents: 1_000)
      Commerce::Order.create!(
        user:,
        status:,
        currency: "CNY",
        subtotal_cents: total_cents,
        total_cents:
      )
    end

    def order_and_item(user:, product:, quantity:)
      order = create_order(user:, status: "pending", total_cents: product.price_cents * quantity)
      item = Commerce::OrderItem.create!(
        order:,
        product:,
        product_name: product.name,
        unit_price_cents: product.price_cents,
        quantity:,
        total_cents: product.price_cents * quantity,
        fulfillment_snapshot: {}
      )
      [ order, item ]
    end

    def paid_order_with_payment(user:)
      order = create_order(user:, status: "paid")
      Payments::Record.create!(
        order:,
        provider: "fake",
        provider_payment_id: "refund-event-#{SecureRandom.hex(8)}",
        status: "succeeded",
        amount_cents: order.total_cents,
        currency: order.currency,
        metadata: { "provider_secret" => "private-refund-provider-secret" }
      )
      order
    end
  end
end
