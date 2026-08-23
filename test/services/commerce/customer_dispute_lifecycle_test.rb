# frozen_string_literal: true

require "test_helper"

module Commerce
  class CustomerDisputeLifecycleTest < ActiveSupport::TestCase
    setup do
      @customer = create_user
      @order = Commerce::Order.create!(
        user: @customer,
        status: "completed",
        currency: "CNY",
        subtotal_cents: 1_000,
        total_cents: 1_000
      )
      @product = Commerce::Product.create!(
        name: "Customer dispute entitlement",
        slug: "customer-dispute-#{SecureRandom.hex(5)}",
        product_type: "digital",
        status: "active",
        price_cents: 1_000,
        currency: "CNY"
      )
      @item = Commerce::OrderItem.create!(
        order: @order,
        product: @product,
        product_name: @product.name,
        unit_price_cents: 1_000,
        quantity: 1,
        total_cents: 1_000,
        fulfillment_snapshot: {}
      )
      @entitlement = Commerce::UserEntitlement.create!(
        user: @customer,
        product: @product,
        source_order_item: @item,
        starts_at: 1.day.ago
      )
      @payment = Payments::Record.create!(
        order: @order,
        provider: "fake",
        provider_payment_id: "customer_dispute_#{SecureRandom.hex(8)}",
        status: "succeeded",
        amount_cents: 1_000,
        currency: "CNY"
      )
    end

    test "create is audited notification-backed and idempotent with a fixed fingerprint" do
      request_id = SecureRandom.uuid
      first = open_case(request_id:, description: "I do not recognize this payment.")
      replay = open_case(request_id:, description: "I do not recognize this payment.")
      conflict = open_case(request_id:, description: "This is a different explanation.")

      assert_predicate first, :success?, first.error
      assert_predicate replay, :success?, replay.error
      assert replay.value.fetch(:idempotent)
      assert_predicate conflict, :failure?
      assert_equal "customer_dispute_idempotency_conflict", conflict.code

      dispute = first.value.fetch(:dispute).reload
      assert_equal @customer.id, dispute.customer_opened_by_id
      assert dispute.customer_provider_pending?
      assert_equal 600, dispute.amount_cents
      assert_equal 600, dispute.liability_cents
      assert_equal "frozen", dispute.rights_status
      assert_equal dispute.id, @entitlement.reload.risk_hold_dispute_id
      assert_equal 1, dispute.events.where(event_type: "customer_opened").count
      assert_equal 1, dispute.rights_actions.where(action: "freeze").count
      assert_equal 1, AuditLog.where(
        action: "commerce.customer_dispute_opened",
        resource_id: dispute.id
      ).count
      assert_equal 1, dispute_notifications(dispute).count
    end

    test "refund and customer dispute reservations are mutually exclusive" do
      refund = Commerce::Refund.create!(
        order: @order,
        payment_record: @payment,
        requested_by: @customer,
        requested_by_customer: true,
        status: "provider_unknown",
        amount_cents: 300
      )
      blocked_dispute = open_case
      assert_predicate blocked_dispute, :failure?
      assert_equal "customer_dispute_refund_in_flight", blocked_dispute.code

      refund.update!(status: "withdrawn", withdrawn_by: @customer, withdrawn_at: Time.current)
      opened = open_case
      assert_predicate opened, :success?, opened.error

      blocked_refund = Commerce::RefundWindow.stub(:within_window?, true) do
        Commerce::RequestRefund.call(
          order: @order,
          user: @customer,
          amount_cents: 100
        )
      end
      assert_predicate blocked_refund, :failure?
      assert_equal "refund_blocked_by_active_dispute", blocked_refund.code
    end

    test "provider webhook binds the existing customer case and replay does not duplicate holds" do
      opened = open_case
      dispute = opened.value.fetch(:dispute)
      occurred_at = Time.current.change(usec: 0)

      channel = apply_channel(
        event_id: "evt-customer-bind",
        dispute_id: "provider-case-1",
        occurred_at:
      )
      replay = apply_channel(
        event_id: "evt-customer-bind",
        dispute_id: "provider-case-1",
        occurred_at:
      )

      assert_predicate channel, :success?, channel.error
      assert_predicate replay, :success?, replay.error
      assert replay.value.fetch(:idempotent)
      assert_equal dispute.id, channel.value.fetch(:dispute).id
      assert_equal 1, @payment.disputes.count
      assert_equal "provider-case-1", dispute.reload.provider_dispute_id
      assert_equal "under_review", dispute.status
      assert_equal 1, dispute.rights_actions.where(action: "freeze").count
      assert_equal 1, dispute.events.where(provider_event_id: "evt-customer-bind").count
      assert_equal 2, dispute_notifications(dispute).count

      withdrawal = withdraw_case(dispute)
      assert_predicate withdrawal, :failure?
      assert_equal "customer_dispute_withdraw_unavailable", withdrawal.code
    end

    test "withdrawal releases exposure and risk hold once while retaining the case" do
      dispute = open_case.value.fetch(:dispute)
      fulfillment = Commerce::Fulfillment.create!(
        order: @order,
        order_item: @item,
        status: "pending"
      )
      request_id = SecureRandom.uuid
      first = nil
      assert_enqueued_with(
        job: Minecraft::EnsureInstanceRunningJob,
        args: [ fulfillment.id ]
      ) do
        first = withdraw_case(dispute, request_id:, reason: "Opened by mistake")
      end
      replay = withdraw_case(dispute, request_id:, reason: "Opened by mistake")
      conflict = withdraw_case(dispute, request_id:, reason: "Changed reason")

      assert_predicate first, :success?, first.error
      assert_predicate replay, :success?, replay.error
      assert replay.value.fetch(:idempotent)
      assert_predicate conflict, :failure?
      assert_equal "customer_dispute_idempotency_conflict", conflict.code

      dispute.reload
      assert_equal "withdrawn", dispute.status
      assert_equal "withdrawn", dispute.resolution
      assert_equal 0, dispute.liability_cents
      assert_equal dispute.amount_cents, dispute.offset_cents
      assert_equal "restored", dispute.rights_status
      assert_nil @entitlement.reload.risk_hold_dispute_id
      assert @entitlement.currently_active?
      assert_equal 1, dispute.events.where(event_type: "customer_withdrawn").count
      assert_equal 1, AuditLog.where(
        action: "commerce.customer_dispute_withdrawn",
        resource_id: dispute.id
      ).count
      assert_equal 2, dispute_notifications(dispute).count
    end

    test "entitlements granted during an active case inherit its hold idempotently" do
      dispute = open_case.value.fetch(:dispute)
      late_product = Commerce::Product.create!(
        name: "Late dispute entitlement",
        slug: "late-dispute-entitlement-#{SecureRandom.hex(5)}",
        product_type: "digital",
        status: "active",
        price_cents: 100,
        currency: "CNY"
      )
      late_item = Commerce::OrderItem.create!(
        order: @order,
        product: late_product,
        product_name: late_product.name,
        unit_price_cents: 100,
        quantity: 1,
        total_cents: 100,
        fulfillment_snapshot: {
          "product_type" => "digital",
          "fulfillment_config" => { "entitlement_days" => 30 }
        }
      )

      first = Commerce::GrantProductEntitlement.call(order_item: late_item)
      replay = Commerce::GrantProductEntitlement.call(order_item: late_item)

      assert_predicate first, :success?, first.error
      assert_predicate replay, :success?, replay.error
      entitlement = first.value
      assert_equal dispute.id, entitlement.reload.risk_hold_dispute_id
      assert_not entitlement.currently_active?
      assert_equal 1, dispute.rights_actions.where(subject: entitlement, action: "freeze").count
      assert_equal 1, dispute.rights_actions.where(subject: @entitlement, action: "freeze").count
    end

    test "memberships granted during an active case skip external grant and inherit the hold" do
      dispute = open_case.value.fetch(:dispute)
      membership_type = Commerce::MembershipType.create!(
        slug: "dispute-late-membership-#{SecureRandom.hex(4)}",
        name: "Dispute late membership",
        duration_mode: "fixed_days",
        duration_days: 30,
        game_permission_enabled: true,
        active: true
      )
      membership_product = Commerce::Product.create!(
        name: "Dispute membership product",
        slug: "dispute-membership-product-#{SecureRandom.hex(5)}",
        product_type: "membership",
        status: "active",
        price_cents: 100,
        currency: "CNY",
        membership_type:
      )
      membership_item = Commerce::OrderItem.create!(
        order: @order,
        product: membership_product,
        product_name: membership_product.name,
        unit_price_cents: 100,
        quantity: 1,
        total_cents: 100,
        fulfillment_snapshot: { "product_type" => "membership" }
      )

      dispatch_count = 0
      first = nil
      replay = nil
      Commerce::DispatchMembershipCommands.stub(
        :call,
        lambda { |**_arguments|
          dispatch_count += 1
          ServiceResult.success
        }
      ) do
        first = Commerce::GrantMembership.call(
          user: @customer,
          membership_type:,
          source_order_item: membership_item
        )
        replay = Commerce::GrantMembership.call(
          user: @customer,
          membership_type:,
          source_order_item: membership_item
        )
      end

      assert_predicate first, :success?, first.error
      assert_predicate replay, :success?, replay.error
      membership = first.value
      assert_equal dispute.id, membership.reload.risk_hold_dispute_id
      assert_not membership.currently_active?
      assert_equal 0, dispatch_count
      assert_equal 1, dispute.rights_actions.where(subject: membership, action: "freeze").count

      other_membership = Commerce::UserMembership.create!(
        user: @customer,
        membership_type:,
        status: "active",
        source: "purchase",
        starts_at: 1.day.ago,
        expires_at: 10.days.from_now
      )
      Commerce::DispatchMembershipCommands.stub(
        :call,
        lambda { |**_arguments|
          dispatch_count += 1
          ServiceResult.success
        }
      ) do
        Commerce::SyncDisputeMembershipRightsJob.perform_now(
          membership.id,
          "revoke",
          "late-membership-aggregate-#{membership.id}"
        )
      end
      assert_equal 0, dispatch_count

      aggregate_keys = []
      Commerce::DispatchMembershipCommands.stub(
        :call,
        lambda { |**arguments|
          aggregate_keys << arguments.fetch(:idempotency_key)
          ServiceResult.success
        }
      ) do
        [ membership, other_membership ].each do |item|
          Commerce::SyncDisputeMembershipRightsJob.perform_now(
            item.id,
            "grant",
            "restore-batch:restore:Commerce::UserMembership:#{item.id}"
          )
        end
      end
      assert_equal 1, aggregate_keys.uniq.size
    end

    test "full refund resolution never reactivates refund-revoked entitlements" do
      dispute = open_case(amount_cents: 1_000).value.fetch(:dispute)
      revoked_at = Time.current.change(usec: 0)
      @order.update!(status: "refunded")
      @entitlement.update!(revoked_at:)
      refund = Commerce::Refund.create!(
        order: @order,
        payment_record: @payment,
        status: "completed",
        restoration_status: "completed",
        amount_cents: 1_000,
        provider_refund_id: "customer_full_refund_#{SecureRandom.hex(4)}"
      )

      result = Commerce::Disputes::RebalanceExposure.call(
        payment_record: @payment,
        trigger_idempotency: "refund:#{refund.id}:customer-dispute"
      )

      assert_predicate result, :success?, result.error
      dispute.reload
      assert_equal "won", dispute.status
      assert_equal "won", dispute.resolution
      assert_equal 0, dispute.liability_cents
      assert_equal "restored", dispute.rights_status
      assert_equal revoked_at, @entitlement.reload.revoked_at
      assert_nil @entitlement.risk_hold_dispute_id
      assert_not @entitlement.currently_active?
      assert_equal 1, dispute.events.where(event_type: "customer_refund_resolved").count
      assert_equal 2, dispute_notifications(dispute).count
    end

    test "connector claims membership state commands with the same ordering key serially" do
      server = Minecraft::Server.create!(
        public_id: "srv_customer_dispute_#{SecureRandom.hex(4)}",
        name: "Customer dispute membership ordering",
        address: "127.0.0.1",
        port: 25_565,
        status: "online"
      )
      ordering_key = "membership-state:#{SecureRandom.hex(16)}"
      grant = Minecraft::ConnectorTask.create!(
        server:,
        task_type: "run_commands",
        status: "pending",
        delivery_id: "customer-dispute-grant-#{SecureRandom.uuid}",
        payload: {
          "commands" => [ "lp user Customer parent add vip" ],
          "ordering_key" => ordering_key
        }
      )
      revoke = Minecraft::ConnectorTask.create!(
        server:,
        task_type: "run_commands",
        status: "pending",
        delivery_id: "customer-dispute-revoke-#{SecureRandom.uuid}",
        payload: {
          "commands" => [ "lp user Customer parent remove vip" ],
          "ordering_key" => ordering_key
        }
      )

      first_claim = Minecraft::TaskDispatcher.call(server:, action: :claim)
      assert_predicate first_claim, :success?, first_claim.error
      assert_equal [ grant.id ], first_claim.value.fetch(:tasks).map(&:id)
      assert revoke.reload.pending?

      completion = Minecraft::TaskDispatcher.call(
        server:,
        task: grant,
        result: { success: true, status: "completed" },
        action: :complete
      )
      assert_predicate completion, :success?, completion.error

      second_claim = Minecraft::TaskDispatcher.call(server:, action: :claim)
      assert_predicate second_claim, :success?, second_claim.error
      assert_equal [ revoke.id ], second_claim.value.fetch(:tasks).map(&:id)
    end

    private

    def open_case(
      request_id: SecureRandom.uuid,
      description: "The payment was not authorized by me.",
      amount_cents: 600
    )
      Commerce::Disputes::CreateCustomerDispute.call(
        order: @order,
        actor: @customer,
        request_id:,
        reason_kind: "unauthorized",
        description:,
        amount_cents:
      )
    end

    def withdraw_case(dispute, request_id: SecureRandom.uuid, reason: nil)
      Commerce::Disputes::WithdrawCustomerDispute.call(
        order: @order,
        dispute:,
        actor: @customer,
        request_id:,
        reason:
      )
    end

    def apply_channel(event_id:, dispute_id:, occurred_at:)
      Commerce::Disputes::ApplyChannelEvent.call(
        provider: @payment.provider,
        provider_event_id: event_id,
        provider_dispute_id: dispute_id,
        payment_record: @payment,
        event_type: "charge.dispute.updated",
        provider_status: "under_review",
        amount_cents: 600,
        currency: @payment.currency,
        occurred_at:,
        sequence: 10,
        risk_level: "high"
      )
    end

    def dispute_notifications(dispute)
      Notification.where(
        user: @customer,
        notification_type: Commerce::Disputes::CustomerNotifier::NOTIFICATION_TYPE
      ).where("metadata ->> 'dispute_public_id' = ?", dispute.public_id)
    end
  end
end
