# frozen_string_literal: true

require "test_helper"

module Payments
  class LatePaymentQueueTest < ActiveSupport::TestCase
    setup do
      Payments::ProviderConfig.find_or_initialize_by(provider: "stripe").tap do |config|
        config.enabled = true
        config.credentials = {
          "secret_key" => "sk_test_late_payment",
          "webhook_secret" => "whsec_late_payment"
        }
        config.save!
        mark_stripe_provider_connection_tested!(config)
      end
      @order = Commerce::Order.create!(
        public_id: "ord_late_payment_#{SecureRandom.hex(6)}",
        order_number: "LATE-#{SecureRandom.hex(6).upcase}",
        user: create_user,
        status: "awaiting_payment",
        subtotal_cents: 1_750,
        discount_cents: 0,
        total_cents: 1_750,
        currency: "CNY"
      )
      @payment = Payments::Record.create!(
        order: @order,
        provider: "stripe",
        provider_mode: "test",
        status: "pending",
        amount_cents: 1_750,
        currency: "CNY",
        provider_payment_id: "cs_test_late_#{SecureRandom.hex(8)}"
      )
    end

    test "a signed paid event for a cancelled order is queued once and completes the webhook" do
      @order.update!(status: "cancelled")
      payload = stripe_payload

      first = process_payload(payload)
      duplicate = process_payload(payload)

      assert first.success?, first.error
      assert first.value[:orphaned]
      assert duplicate.success?, duplicate.error
      assert duplicate.value[:idempotent]

      review_case = Payments::LatePaymentCase.sole
      event = Payments::WebhookEvent.find_by!(
        provider: "stripe",
        event_id: JSON.parse(payload).fetch("id")
      )

      assert event.processed?
      assert_equal event, review_case.webhook_event
      assert_equal @payment, review_case.payment_record
      assert_equal @order, review_case.order
      assert_equal "order_cancelled", review_case.reason
      assert_equal "open", review_case.status
      assert_equal @payment.amount_cents, review_case.amount_cents
      assert_equal "succeeded", @payment.reload.status
      assert_equal true, @payment.metadata["orphaned"]
      assert_equal "cancelled", @order.reload.status
    end

    test "a signed paid event after the payment window expires enters the queue" do
      SiteSetting.set("store.pending_order_expiry_minutes", "30")
      @order.update!(created_at: 2.hours.ago)

      result = process_payload(stripe_payload)

      assert result.success?, result.error
      assert result.value[:orphaned]
      review_case = Payments::LatePaymentCase.sole
      assert_equal "order_expired", review_case.reason
      assert_equal "succeeded", @payment.reload.status
      assert_equal "awaiting_payment", @order.reload.status
    end

    test "payment success and queue insertion roll back together when queue persistence fails" do
      @order.update!(status: "cancelled")

      with_queue_failure do
        result = process_payload(stripe_payload)
        assert result.failure?
        assert_equal "database_unavailable", result.code
      end

      assert_equal "pending", @payment.reload.status
      refute @payment.metadata["orphaned"]
      assert_empty Payments::LatePaymentCase.where(payment_record: @payment)
    end

    test "an unverified or non-succeeded source cannot be inserted directly" do
      event = Payments::WebhookEvent.create!(
        provider: "stripe",
        event_id: "evt_unverified_#{SecureRandom.hex(6)}",
        event_type: "payment_intent.succeeded",
        status: "received",
        payload: {}
      )

      assert_raises(ArgumentError) do
        Payments::LatePaymentCase.enqueue_from_verified_webhook!(
          payment_record: @payment,
          webhook_event: event,
          reason: "order_cancelled"
        )
      end
      assert_empty Payments::LatePaymentCase.where(payment_record: @payment)
    end

    private

    def stripe_payload
      {
        id: "evt_late_#{SecureRandom.hex(8)}",
        object: "event",
        type: "checkout.session.completed",
        data: {
          object: {
            id: @payment.provider_payment_id,
            object: "checkout.session",
            livemode: false,
            payment_status: "paid",
            amount_total: @payment.amount_cents,
            currency: @payment.currency.downcase,
            client_reference_id: @order.public_id,
            payment_intent: "pi_late_#{SecureRandom.hex(8)}",
            metadata: {
              payment_record_id: @payment.id.to_s,
              order_public_id: @order.public_id
            }
          }
        }
      }.to_json
    end

    def process_payload(payload)
      parsed = JSON.parse(payload)
      Payments::WebhookProcessor.call(
        provider: "stripe",
        event_id: parsed.fetch("id"),
        event_type: parsed.fetch("type"),
        payload: payload,
        signature: stripe_webhook_signature(payload, "whsec_late_payment")
      )
    end

    def with_queue_failure
      singleton = Payments::LatePaymentCase.singleton_class
      original = singleton.instance_method(:enqueue_from_verified_webhook!)
      singleton.define_method(:enqueue_from_verified_webhook!) do |**|
        raise ActiveRecord::ConnectionNotEstablished, "queue unavailable"
      end
      yield
    ensure
      singleton.define_method(:enqueue_from_verified_webhook!, original)
    end
  end

  class AcknowledgeLatePaymentCaseTest < ActiveSupport::TestCase
    setup do
      @reviewer = create_user
      grant_permission(@reviewer, Payments::LatePaymentCase::PERMISSION)
      @customer = create_user
      @order = Commerce::Order.create!(
        public_id: "ord_late_review_#{SecureRandom.hex(6)}",
        order_number: "REVIEW-#{SecureRandom.hex(6).upcase}",
        user: @customer,
        status: "cancelled",
        subtotal_cents: 2_400,
        discount_cents: 0,
        total_cents: 2_400,
        currency: "CNY"
      )
      @payment = Payments::Record.create!(
        order: @order,
        provider: "stripe",
        status: "succeeded",
        amount_cents: 2_400,
        currency: "CNY",
        provider_payment_id: "pi_late_review_#{SecureRandom.hex(8)}",
        metadata: {
          "orphaned" => true,
          "orphan_reason" => "order_cancelled"
        }
      )
      @event = verified_event
      @review_case = Payments::LatePaymentCase.enqueue_from_verified_webhook!(
        payment_record: @payment,
        webhook_event: @event,
        reason: "order_cancelled"
      )
      @token = Payments::LatePaymentReviewToken.issue(@review_case)
    end

    test "acknowledgement requires the exact order number and does not mutate funds or order state" do
      invalid = acknowledge(confirmation: "wrong-order")
      assert invalid.failure?
      assert_equal "confirmation_mismatch", invalid.code
      assert @review_case.reload.open?

      payment_before = @payment.attributes.slice(
        "status",
        "amount_cents",
        "currency",
        "provider_payment_id",
        "metadata"
      )
      order_before = @order.attributes.slice("status", "total_cents", "currency")
      refund_count = Commerce::Refund.count

      result = acknowledge

      assert result.success?, result.error
      assert_not result.value[:idempotent]
      assert @review_case.reload.acknowledged?
      assert_equal "refund_required", @review_case.disposition
      assert_equal @reviewer, @review_case.acknowledged_by
      assert_equal payment_before, @payment.reload.attributes.slice(*payment_before.keys)
      assert_equal order_before, @order.reload.attributes.slice(*order_before.keys)
      assert_equal refund_count, Commerce::Refund.count

      audit = AuditLog.where(
        action: "admin.payment_late_payment_acknowledged",
        resource_type: "Payments::LatePaymentCase",
        resource_id: @review_case.id
      ).sole
      assert_equal @reviewer, audit.actor
      assert_equal "refund_required", audit.metadata["disposition"]
      assert_equal "Verified in Stripe; provider refund must be opened.", audit.reason
    end

    test "an identical retry is idempotent and does not duplicate the audit entry" do
      first = acknowledge
      second = acknowledge

      assert first.success?
      assert second.success?
      assert second.value[:idempotent]
      assert_equal 1, AuditLog.where(
        action: "admin.payment_late_payment_acknowledged",
        resource_type: "Payments::LatePaymentCase",
        resource_id: @review_case.id
      ).count
    end

    test "a different second acknowledgement is rejected" do
      assert acknowledge.success?

      different = Payments::AcknowledgeLatePaymentCase.call(
        review_case: @review_case,
        actor: @reviewer,
        token: @token,
        confirmation: @order.order_number,
        disposition: "contact_customer",
        note: "Contact the customer before deciding on the refund."
      )

      assert different.failure?
      assert_equal "already_acknowledged", different.code
      assert_equal "refund_required", @review_case.reload.disposition
    end

    test "the dedicated permission is required" do
      unauthorized = create_user
      result = Payments::AcknowledgeLatePaymentCase.call(
        review_case: @review_case,
        actor: unauthorized,
        token: @token,
        confirmation: @order.order_number,
        disposition: "refund_required",
        note: "Verified in Stripe; provider refund must be opened."
      )

      assert result.failure?
      assert_equal "forbidden", result.code
      assert @review_case.reload.open?
    end

    private

    def acknowledge(confirmation: @order.order_number)
      Payments::AcknowledgeLatePaymentCase.call(
        review_case: @review_case,
        actor: @reviewer,
        token: @token,
        confirmation: confirmation,
        disposition: "refund_required",
        note: "Verified in Stripe; provider refund must be opened.",
        ip_address: "127.0.0.1",
        user_agent: "Test browser"
      )
    end

    def verified_event
      payload = {
        "type" => "payment_intent.succeeded",
        "data" => {
          "object" => {
            "id" => @payment.provider_payment_id,
            "object" => "payment_intent",
            "livemode" => false,
            "amount" => @payment.amount_cents,
            "amount_received" => @payment.amount_cents,
            "currency" => @payment.currency.downcase,
            "metadata" => {
              "payment_record_id" => @payment.id.to_s,
              "order_public_id" => @order.public_id
            }
          }
        }
      }
      Payments::WebhookEvent.create!(
        provider: "stripe",
        event_id: "evt_late_review_#{SecureRandom.hex(8)}",
        event_type: "payment_intent.succeeded",
        status: "processed",
        payload: payload,
        payload_digest: Payments::WebhookPayload.digest(
          payload,
          event_type: "payment_intent.succeeded"
        ),
        verified_at: Time.current,
        processed_at: Time.current
      )
    end
  end
end
