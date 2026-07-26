# frozen_string_literal: true

require "test_helper"

module Payments
  class OperationsSerializerTest < ActiveSupport::TestCase
    setup do
      @order = Commerce::Order.create!(
        public_id: "ord_ops_serializer_#{SecureRandom.hex(6)}",
        order_number: "OPS-SERIALIZER-#{SecureRandom.hex(4).upcase}",
        user: create_user,
        status: "paid",
        subtotal_cents: 2_000,
        discount_cents: 0,
        total_cents: 2_000,
        currency: "CNY"
      )
      @payment = Payments::Record.create!(
        order: @order,
        provider: "stripe",
        status: "succeeded",
        amount_cents: 2_000,
        currency: "CNY",
        provider_payment_id: "pi_secret_reference_1234",
        metadata: {
          "orphaned" => true,
          "orphan_reason" => "order_cancelled",
          "customer_email" => "customer-private@example.com",
          "secret_key" => "sk_test_must_not_render"
        }
      )
    end

    test "payment serialization allowlists metadata and masks provider references" do
      serialized = Payments::OperationsSerializer.record(@payment)
      rendered = serialized.to_json

      assert serialized[:orphaned]
      assert_equal "order_cancelled", serialized[:orphan_reason]
      assert_equal "pi_••••1234", serialized[:provider_reference]
      refute_includes rendered, "pi_secret_reference_1234"
      refute_includes rendered, "customer-private@example.com"
      refute_includes rendered, "sk_test_must_not_render"
      refute serialized.key?(:metadata)
    end

    test "webhook serialization omits payload and error details" do
      event = Payments::WebhookEvent.create!(
        provider: "stripe",
        event_id: "evt_secret_reference_5678",
        event_type: "payment_intent.succeeded",
        status: "failed",
        error_message: "customer-private@example.com sk_test_must_not_render",
        payload: {
          "customer_email" => "customer-private@example.com",
          "secret" => "whsec_must_not_render"
        }
      )

      serialized = Payments::OperationsSerializer.webhook(event)
      rendered = serialized.to_json

      assert serialized[:error_recorded]
      assert_equal "evt_••••5678", serialized[:event_reference]
      refute_includes rendered, event.event_id
      refute_includes rendered, "customer-private@example.com"
      refute_includes rendered, "whsec_must_not_render"
      refute serialized.key?(:payload)
      refute serialized.key?(:error_message)
    end

    test "refund serialization omits reason and provider metadata" do
      refund = Commerce::Refund.create!(
        order: @order,
        payment_record: @payment,
        amount_cents: 500,
        status: "approved",
        reason: "Customer customer-private@example.com requested it",
        provider_refund_id: "re_secret_reference_9012",
        provider_status: "pending",
        provider_error_code: "provider_pending",
        provider_metadata: {
          "customer_email" => "customer-private@example.com",
          "secret" => "sk_test_must_not_render"
        },
        processing_started_at: 10.minutes.ago
      )

      serialized = Payments::OperationsSerializer.refund(refund)
      rendered = serialized.to_json

      assert serialized[:stale]
      assert_equal "re_••••9012", serialized[:provider_reference]
      assert_equal "pending", serialized[:provider_status]
      refute_includes rendered, refund.provider_refund_id
      refute_includes rendered, "customer-private@example.com"
      refute_includes rendered, "sk_test_must_not_render"
      refute serialized.key?(:reason)
      refute serialized.key?(:provider_metadata)
    end

    test "filter values from persisted provider data are token allowlisted" do
      options = Payments::OperationsSerializer.filter_options(
        providers: [ "stripe", "private@example.com" ],
        statuses: [ "failed", "failed with private detail" ],
        provider_statuses: [ "pending", "customer@example.com" ]
      )
      filters = Payments::OperationsSerializer.filters(
        provider: "private@example.com",
        status: "failed",
        provider_status: "customer@example.com",
        q: "operator-entered query"
      )

      assert_equal [ "stripe" ], options[:providers]
      assert_equal [ "failed" ], options[:statuses]
      assert_equal [ "pending" ], options[:provider_statuses]
      assert_nil filters[:provider]
      assert_equal "failed", filters[:status]
      assert_nil filters[:provider_status]
    end
  end
end
