# frozen_string_literal: true

require "test_helper"

module Payments
  class StripeReconciliationAdapterContractTest < ActiveSupport::TestCase
    class RecordingResource
      attr_reader :requests

      def initialize(outcomes)
        @outcomes = outcomes.dup
        @requests = []
      end

      def list(params)
        @requests << params.deep_dup
        outcome = @outcomes.shift
        raise outcome if outcome.is_a?(Exception)

        outcome
      end
    end

    V1Resources = Data.define(:payment_intents, :refunds)
    FakeClient = Data.define(:v1)

    test "payment pages use bounded Stripe pagination and return the last reference as cursor" do
      payment_resource = RecordingResource.new(
        [
          {
            data: [
              payment_object(id: "pi_page_one"),
              payment_object(id: "pi_page_two")
            ],
            has_more: true
          },
          { data: [], has_more: false }
        ]
      )
      adapter = build_adapter(payment_resource: payment_resource)
      window_start = Time.utc(2026, 7, 20)
      window_end = window_start + 1.day

      first = adapter.payment_page(window_start: window_start, window_end: window_end)
      second = adapter.payment_page(
        window_start: window_start,
        window_end: window_end,
        cursor: first.value[:next_cursor]
      )

      assert first.success?
      assert_equal %w[pi_page_one pi_page_two],
        first.value[:items].pluck(:reference)
      assert_equal "pi_page_two", first.value[:next_cursor]
      assert second.success?
      assert_nil second.value[:next_cursor]
      assert_equal(
        {
          created: { gte: window_start.to_i, lt: window_end.to_i },
          limit: Payments::StripeReconciliationAdapter::PAGE_SIZE
        },
        payment_resource.requests.first
      )
      assert_equal "pi_page_two", payment_resource.requests.second[:starting_after]
      assert_equal(
        { gte: window_start.to_i, lt: window_end.to_i },
        payment_resource.requests.second[:created]
      )
    end

    test "refund pages pass their cursor and normalize amount currency and metadata" do
      refund_resource = RecordingResource.new(
        [
          {
            "data" => [
              refund_object(
                id: "re_metadata_1234",
                amount: 725,
                currency: "usd",
                metadata: {
                  "mcweb_refund_id" => "123",
                  "payment_record_id" => "456",
                  "order_public_id" => "ord_public-789",
                  "secret_key" => "must_not_be_copied"
                }
              )
            ],
            "has_more" => false
          }
        ]
      )
      adapter = build_adapter(refund_resource: refund_resource)

      result = adapter.refund_page(
        window_start: Time.utc(2026, 7, 20),
        window_end: Time.utc(2026, 7, 21),
        cursor: "re_previous_0001"
      )

      assert result.success?
      assert_equal(
        {
          reference: "re_metadata_1234",
          payment_reference: "pi_refund_payment_0001",
          status: "succeeded",
          amount_cents: 725,
          currency: "USD",
          local_refund_id: 123,
          local_payment_record_id: 456,
          local_order_public_id: "ord_public-789",
          metadata_valid: true
        },
        result.value[:items].sole
      )
      assert_equal "re_previous_0001", refund_resource.requests.sole[:starting_after]
      refute_includes result.value.to_json, "must_not_be_copied"
      refute_includes result.value.to_json, "secret_key"
    end

    test "payments use amount received only after success and uppercase ISO currency" do
      payment_resource = RecordingResource.new(
        [
          {
            data: [
              payment_object(
                id: "pi_succeeded_1001",
                status: "succeeded",
                amount: 2_000,
                amount_received: 1_900,
                currency: "cny"
              ),
              payment_object(
                id: "pi_processing_1002",
                status: "processing",
                amount: 2_100,
                amount_received: 400,
                currency: "eur"
              )
            ],
            has_more: false
          }
        ]
      )

      result = build_adapter(payment_resource: payment_resource).payment_page(
        window_start: Time.utc(2026, 7, 20),
        window_end: Time.utc(2026, 7, 21)
      )

      assert result.success?
      succeeded, processing = result.value[:items]
      assert_equal [ 1_900, "CNY" ],
        succeeded.values_at(:amount_cents, :currency)
      assert_equal [ 2_100, "EUR" ],
        processing.values_at(:amount_cents, :currency)
    end

    test "metadata identifiers are allowlisted and malformed identifiers fail closed" do
      payment_resource = RecordingResource.new(
        [
          {
            data: [
              payment_object(
                id: "pi_metadata_bad",
                metadata: {
                  "payment_record_id" => "01",
                  "order_public_id" => "order/unsafe",
                  "customer_email" => "private@example.com"
                }
              )
            ],
            has_more: false
          }
        ]
      )

      result = build_adapter(payment_resource: payment_resource).payment_page(
        window_start: Time.utc(2026, 7, 20),
        window_end: Time.utc(2026, 7, 21)
      )

      assert result.success?
      item = result.value[:items].sole
      assert_nil item[:local_payment_record_id]
      assert_nil item[:local_order_public_id]
      refute item[:metadata_valid]
      refute_includes item.to_json, "private@example.com"
      refute_includes item.to_json, "customer_email"
    end

    test "environment must match both test and live Stripe records" do
      mismatch_resource = RecordingResource.new(
        [
          {
            data: [ payment_object(id: "pi_live_mismatch", livemode: true) ],
            has_more: false
          }
        ]
      )

      mismatch = build_adapter(payment_resource: mismatch_resource).payment_page(
        window_start: Time.utc(2026, 7, 20),
        window_end: Time.utc(2026, 7, 21)
      )

      assert mismatch.failure?
      assert_equal "environment_mismatch", mismatch.code

      live_resource = RecordingResource.new(
        [
          {
            data: [ payment_object(id: "pi_live_match", livemode: true) ],
            has_more: false
          }
        ]
      )
      live = build_adapter(
        payment_resource: live_resource,
        expected_mode: "live"
      ).payment_page(
        window_start: Time.utc(2026, 7, 20),
        window_end: Time.utc(2026, 7, 21)
      )

      assert live.success?
      assert_equal "pi_live_match", live.value[:items].sole[:reference]
    end

    test "invalid amounts currencies and nonadvancing pages are rejected" do
      invalid_objects = [
        payment_object(id: "pi_negative", amount: -1, amount_received: -1),
        payment_object(id: "pi_fractional", amount: 10.5, amount_received: 10.5),
        payment_object(id: "pi_currency", currency: "USDX")
      ]

      invalid_objects.each do |object|
        resource = RecordingResource.new(
          [ { data: [ object ], has_more: false } ]
        )
        result = build_adapter(payment_resource: resource).payment_page(
          window_start: Time.utc(2026, 7, 20),
          window_end: Time.utc(2026, 7, 21)
        )

        assert result.failure?
        assert_equal "invalid_provider_response", result.code
      end

      stalled_resource = RecordingResource.new(
        [
          {
            data: [ payment_object(id: "pi_same_cursor") ],
            has_more: true
          }
        ]
      )
      stalled = build_adapter(payment_resource: stalled_resource).payment_page(
        window_start: Time.utc(2026, 7, 20),
        window_end: Time.utc(2026, 7, 21),
        cursor: "pi_same_cursor"
      )

      assert stalled.failure?
      assert_equal "invalid_provider_response", stalled.code
    end

    test "Stripe failures map to stable allowlisted codes without provider messages" do
      mappings = {
        Stripe::AuthenticationError => "authentication_failed",
        Stripe::PermissionError => "permission_denied",
        Stripe::RateLimitError => "rate_limited",
        Stripe::APIConnectionError => "provider_unavailable",
        Stripe::APIError => "provider_error"
      }

      mappings.each do |error_class, expected_code|
        resource = RecordingResource.new(
          [ error_class.new("provider secret must never escape") ]
        )
        result = build_adapter(payment_resource: resource).payment_page(
          window_start: Time.utc(2026, 7, 20),
          window_end: Time.utc(2026, 7, 21)
        )

        assert result.failure?
        assert_equal expected_code, result.code
        refute_includes result.error, "provider secret"
      end
    end

    test "malformed Stripe page shapes are rejected without partial output" do
      malformed_pages = [
        { data: "not-an-array", has_more: false },
        { data: [], has_more: "false" },
        { data: [], has_more: true }
      ]

      malformed_pages.each do |page|
        resource = RecordingResource.new([ page ])
        result = build_adapter(payment_resource: resource).payment_page(
          window_start: Time.utc(2026, 7, 20),
          window_end: Time.utc(2026, 7, 21)
        )

        assert result.failure?
        assert_equal "invalid_provider_response", result.code
        assert_nil result.value
      end
    end

    private

    def build_adapter(payment_resource: nil, refund_resource: nil, expected_mode: "test")
      payment_resource ||= RecordingResource.new(
        [ { data: [], has_more: false } ]
      )
      refund_resource ||= RecordingResource.new(
        [ { data: [], has_more: false } ]
      )
      client = FakeClient.new(
        V1Resources.new(
          payment_intents: payment_resource,
          refunds: refund_resource
        )
      )

      Payments::StripeReconciliationAdapter.new(
        expected_mode: expected_mode,
        client: client
      )
    end

    def payment_object(id:, status: "succeeded", amount: 1_000,
                       amount_received: amount, currency: "cny", livemode: false,
                       metadata: {})
      {
        id: id,
        status: status,
        amount: amount,
        amount_received: amount_received,
        currency: currency,
        livemode: livemode,
        metadata: metadata
      }
    end

    def refund_object(id:, payment_intent: "pi_refund_payment_0001",
                      status: "succeeded", amount: 300, currency: "cny",
                      livemode: false, metadata: {})
      {
        id: id,
        payment_intent: payment_intent,
        status: status,
        amount: amount,
        currency: currency,
        livemode: livemode,
        metadata: metadata
      }
    end
  end
end
