# frozen_string_literal: true

require "test_helper"

module Payments
  class DailyReconciliationTest < ActiveSupport::TestCase
    class FakeAdapter
      attr_accessor :payment_pages, :refund_pages
      attr_reader :calls

      def initialize(payment_pages: nil, refund_pages: nil)
        @payment_pages = payment_pages || { nil => { items: [], next_cursor: nil } }
        @refund_pages = refund_pages || { nil => { items: [], next_cursor: nil } }
        @calls = []
      end

      def payment_page(window_start:, window_end:, cursor: nil)
        page(:payment, @payment_pages, window_start, window_end, cursor)
      end

      def refund_page(window_start:, window_end:, cursor: nil)
        page(:refund, @refund_pages, window_start, window_end, cursor)
      end

      private

      def page(subject, pages, window_start, window_end, cursor)
        @calls << [ subject, cursor, window_start, window_end ]
        value = pages.fetch(cursor)
        return value if value.is_a?(ServiceResult)

        ServiceResult.success(value)
      end
    end

    setup do
      @date = Date.new(2026, 7, 20)
      @window_start = Time.utc(2026, 7, 20)
      @now = Time.utc(2026, 7, 29, 12)
      configure_stripe!
    end

    test "disabled checkout still reconciles with a current account identity" do
      config = Payments::ProviderConfig.find_by!(provider: "stripe")
      config.update!(enabled: false)
      adapter = FakeAdapter.new

      refute config.checkout_ready?
      assert config.reconciliation_ready?

      result = reconcile(adapter: adapter)

      assert result.success?, result.error
      refute result.value[:skipped]
      assert_equal %i[payment refund], adapter.calls.map(&:first)
      assert_equal "completed", result.value[:run].reload.status
    end

    test "reconciliation skips before contacting Stripe when identity proof is stale" do
      config = Payments::ProviderConfig.find_by!(provider: "stripe")
      config.update!(
        last_connection_test_status: "failed",
        last_connection_test_error_code: "configuration_changed",
        last_connection_test_credential_revision: nil
      )
      adapter = FakeAdapter.new

      refute config.reconciliation_ready?

      result = reconcile(adapter: adapter)

      assert result.success?, result.error
      assert result.value[:skipped]
      assert_empty adapter.calls
      assert_equal "provider_not_configured",
        result.value[:run].reload.failure_code
    end

    test "client construction failures are recorded after the run lease is claimed" do
      result = nil
      Payments::StripeReconciliationAdapter.stub(
        :new,
        ->(**) { raise "client construction failed" }
      ) do
        result = Payments::ReconcileDay.call(
          date: @date,
          clock: -> { @now }
        )
      end

      assert result.failure?
      assert_equal "reconciliation_internal_error", result.code
      run = Payments::ReconciliationRun.find_by!(
        provider: "stripe",
        mode: "test",
        window_start: @window_start
      )
      assert_predicate run, :failed?
      assert_equal "reconciliation_internal_error", run.failure_code
      assert_nil run.processing_token
    end

    test "a manually reserved run fails closed if the Stripe identity changes before execution" do
      config = Payments::ProviderConfig.find_by!(provider: "stripe")
      run = Payments::ReconciliationRun.create!(
        provider: "stripe",
        mode: "test",
        window_start: @window_start,
        window_end: @window_start + 1.day,
        status: "pending",
        phase: "payments"
      )
      binding = Payments::ReconciliationConfigBinding.generate(
        config: config,
        run: run
      )

      config.update!(
        mode: "live",
        credentials: {
          "secret_key" => "sk_live_reconciliation_replaced",
          "webhook_secret" => "whsec_reconciliation_replaced"
        }
      )
      mark_stripe_provider_connection_tested!(
        config,
        account_id: "acct_REPLACED12345678"
      )
      adapter = FakeAdapter.new

      result = nil
      assert_no_difference "Payments::ReconciliationRun.count" do
        result = Payments::ReconcileDay.call(
          date: @date,
          adapter: adapter,
          refresh: false,
          clock: -> { @now },
          reserved_run_id: run.id,
          expected_config_binding: binding
        )
      end

      assert result.failure?
      assert_equal "provider_configuration_changed", result.code
      assert_empty adapter.calls
      assert run.reload.failed?
      assert_equal "provider_configuration_changed", run.failure_code
      refute Payments::ReconciliationRun.exists?(
        provider: "stripe",
        mode: "live",
        window_start: @window_start
      )
    end

    test "full consistent metadata safely identifies records whose provider references were not committed" do
      order, payment = create_payment(
        status: "succeeded",
        order_status: "paid",
        provider_payment_id: "cs_crash_recovery"
      )
      refund = Commerce::Refund.create!(
        order: order,
        payment_record: payment,
        status: "completed",
        amount_cents: 300,
        provider_refund_id: nil,
        created_at: @window_start + 3.hours,
        updated_at: @window_start + 3.hours
      )
      adapter = FakeAdapter.new(
        payment_pages: {
          nil => {
            items: [
              payment_item(
                payment,
                reference: "pi_crash_recovery",
                status: "succeeded"
              )
            ],
            next_cursor: nil
          }
        },
        refund_pages: {
          nil => {
            items: [
              refund_item(
                refund,
                reference: "re_crash_recovery",
                payment_reference: "pi_crash_recovery",
                status: "succeeded"
              )
            ],
            next_cursor: nil
          }
        }
      )

      result = reconcile(adapter: adapter)

      assert result.success?
      discrepancies = result.value[:run].discrepancies.order(:kind)
      assert_equal %w[
        payment_reference_missing
        refund_payment_mismatch
        refund_reference_missing
      ],
        discrepancies.pluck(:kind)
      assert_equal payment.id,
        discrepancies.find_by!(kind: "payment_reference_missing").payment_record_id
      assert_equal refund.id,
        discrepancies.find_by!(kind: "refund_reference_missing").refund_id
      refund_owner_mismatch = discrepancies.find_by!(
        kind: "refund_payment_mismatch"
      )
      assert_equal refund.id, refund_owner_mismatch.refund_id
      assert_equal payment.id, refund_owner_mismatch.payment_record_id
      assert_equal order.id, refund_owner_mismatch.store_order_id
      refute discrepancies.exists?(kind: "payment_metadata_mismatch")
      refute discrepancies.exists?(kind: "refund_metadata_mismatch")
    end

    test "conflicting provider metadata fails closed and never binds the wrong local payment" do
      first_order, first_payment = create_payment(
        status: "succeeded",
        order_status: "paid",
        provider_payment_id: "pi_reference_owner"
      )
      second_order, second_payment = create_payment(
        status: "succeeded",
        order_status: "paid",
        provider_payment_id: "pi_other",
        created_at: @window_start - 3.days
      )
      item = payment_item(
        first_payment,
        reference: "pi_reference_owner",
        status: "succeeded"
      ).merge(
        local_payment_record_id: second_payment.id,
        local_order_public_id: second_order.public_id
      )

      result = reconcile(
        adapter: FakeAdapter.new(
          payment_pages: { nil => { items: [ item ], next_cursor: nil } }
        )
      )

      discrepancy = result.value[:run].discrepancies.find_by!(
        kind: "payment_metadata_mismatch"
      )
      assert_nil discrepancy.payment_record_id
      assert_nil discrepancy.store_order_id
      refute result.value[:run].discrepancies.exists?(
        kind: "provider_payment_missing_local"
      )
      assert_equal first_order.id, first_payment.store_order_id
    end

    test "adjacent observations are trusted only after that run completes" do
      _order, payment = create_payment(
        status: "succeeded",
        order_status: "paid",
        provider_payment_id: "pi_boundary",
        metadata: { "stripe_payment_intent_id" => "pi_boundary" }
      )
      adjacent = Payments::ReconciliationRun.create!(
        provider: "stripe",
        mode: "test",
        window_start: @window_start + 1.day,
        window_end: @window_start + 2.days,
        status: "failed",
        phase: "payments",
        failure_code: "provider_unavailable",
        failed_at: @now,
        refresh_count: 1,
        refresh_started_at: @now - 1.minute
      )
      Payments::ReconciliationObservation.create!(
        run: adjacent,
        subject_type: "payment",
        reference_digest: reference_digest("pi_boundary")
      )

      first = reconcile(adapter: FakeAdapter.new)
      missing = first.value[:run].discrepancies.find_by!(
        kind: "local_payment_missing_provider"
      )
      assert missing.open?

      adjacent.update!(
        status: "completed",
        phase: "completed",
        failure_code: nil,
        failed_at: nil,
        completed_at: @now
      )
      @now += 1.minute
      second = reconcile(adapter: FakeAdapter.new, refresh: true)

      assert second.success?
      assert missing.reload.resolved?
      assert_equal 1, adjacent.observations.count
      assert_equal payment.id, missing.payment_record_id
    end

    test "rolling refresh detects a late provider status and resolves it after local catch up" do
      order, payment = create_payment(
        status: "processing",
        order_status: "awaiting_payment",
        provider_payment_id: "pi_late_status",
        metadata: { "stripe_payment_intent_id" => "pi_late_status" }
      )
      adapter = FakeAdapter.new(
        payment_pages: {
          nil => {
            items: [ payment_item(payment, reference: "pi_late_status", status: "processing") ],
            next_cursor: nil
          }
        }
      )

      first = reconcile(adapter: adapter)
      assert first.success?
      assert_empty first.value[:run].discrepancies

      adapter.payment_pages = {
        nil => {
          items: [ payment_item(payment, reference: "pi_late_status", status: "succeeded") ],
          next_cursor: nil
        }
      }
      @now += 1.minute
      second = reconcile(adapter: adapter, refresh: true)
      run = second.value[:run]
      assert run.discrepancies.exists?(kind: "payment_status_mismatch", status: "open")
      assert run.discrepancies.exists?(kind: "order_status_mismatch", status: "open")
      assert_equal 1, run.observations.count

      payment.update!(status: "succeeded")
      order.update!(status: "paid")
      @now += 1.minute
      third = reconcile(adapter: adapter, refresh: true)

      assert third.success?
      assert_equal 3, third.value[:run].refresh_count
      assert_equal 2, third.value[:run].discrepancies.where(status: "resolved").count
      refute third.value[:run].discrepancies.open.exists?
    end

    test "a failed provider page resumes from its committed cursor" do
      _first_order, first_payment = create_payment(
        status: "succeeded",
        order_status: "paid",
        provider_payment_id: "pi_cursor_one",
        metadata: { "stripe_payment_intent_id" => "pi_cursor_one" }
      )
      _second_order, second_payment = create_payment(
        status: "succeeded",
        order_status: "paid",
        provider_payment_id: "pi_cursor_two",
        metadata: { "stripe_payment_intent_id" => "pi_cursor_two" }
      )
      first_adapter = FakeAdapter.new(
        payment_pages: {
          nil => {
            items: [ payment_item(first_payment, reference: "pi_cursor_one") ],
            next_cursor: "pi_cursor_one"
          },
          "pi_cursor_one" => ServiceResult.failure(
            error: "Provider unavailable.",
            code: "provider_unavailable"
          )
        }
      )

      first = reconcile(adapter: first_adapter)
      assert first.failure?
      run = Payments::ReconciliationRun.find_by!(window_start: @window_start)
      assert run.failed?
      assert_equal "pi_cursor_one", run.payment_cursor
      assert_equal 1, run.payments_checked

      second_adapter = FakeAdapter.new(
        payment_pages: {
          "pi_cursor_one" => {
            items: [ payment_item(second_payment, reference: "pi_cursor_two") ],
            next_cursor: nil
          }
        }
      )
      second = reconcile(adapter: second_adapter)

      assert second.success?
      assert second.value[:run].completed?
      assert_equal [ "pi_cursor_one" ],
        second_adapter.calls.select { |call| call.first == :payment }.map { |call| call[1] }
      assert_equal 2, second.value[:run].payments_checked
    end

    test "review tokens become stale after lock or lifecycle changes" do
      _order, payment = create_payment(
        status: "succeeded",
        order_status: "paid",
        provider_payment_id: "pi_token",
        metadata: { "stripe_payment_intent_id" => "pi_token" }
      )
      result = reconcile(
        adapter: FakeAdapter.new(
          payment_pages: {
            nil => {
              items: [
                payment_item(payment, reference: "pi_token", amount_cents: 9_999)
              ],
              next_cursor: nil
            }
          }
        )
      )
      discrepancy = result.value[:run].discrepancies.find_by!(
        kind: "payment_amount_mismatch"
      )

      token = Payments::ReconciliationReviewToken.issue(discrepancy)
      assert Payments::ReconciliationReviewToken.valid?(token, discrepancy)
      discrepancy.update!(last_seen_at: discrepancy.last_seen_at + 1.second)
      refute Payments::ReconciliationReviewToken.valid?(token, discrepancy.reload)

      lifecycle_token = Payments::ReconciliationReviewToken.issue(discrepancy)
      discrepancy.update!(status: "resolved", resolved_at: @now)
      refute Payments::ReconciliationReviewToken.valid?(
        lifecycle_token,
        discrepancy.reload
      )
    end

    test "abandoned pending and cancelled checkouts without a payment intent are not financial discrepancies" do
      create_payment(
        status: "pending",
        order_status: "awaiting_payment",
        provider_payment_id: "cs_pending_without_intent"
      )
      create_payment(
        status: "cancelled",
        order_status: "cancelled",
        provider_payment_id: "cs_cancelled_without_intent"
      )

      result = reconcile(adapter: FakeAdapter.new)

      assert result.success?
      refute result.value[:run].discrepancies.exists?(
        kind: "payment_reference_missing"
      )
    end

    private

    def configure_stripe!
      config = Payments::ProviderConfig.find_or_initialize_by(provider: "stripe")
      config.assign_attributes(
        enabled: true,
        mode: "test",
        credentials: {
          "secret_key" => "sk_test_reconciliation",
          "webhook_secret" => "whsec_reconciliation"
        }
      )
      config.save!
      mark_stripe_provider_connection_tested!(config)
    end

    def reconcile(adapter:, refresh: false)
      Payments::ReconcileDay.call(
        date: @date,
        adapter: adapter,
        refresh: refresh,
        clock: -> { @now }
      )
    end

    def create_payment(status:, order_status:, provider_payment_id:, metadata: {},
                       created_at: @window_start + 2.hours)
      customer = create_user
      order = Commerce::Order.create!(
        public_id: "ord_recon_#{SecureRandom.hex(6)}",
        order_number: "RECON-#{SecureRandom.hex(5).upcase}",
        user: customer,
        status: order_status,
        subtotal_cents: 1_000,
        discount_cents: 0,
        total_cents: 1_000,
        currency: "CNY",
        created_at: created_at,
        updated_at: created_at
      )
      payment = Payments::Record.create!(
        order: order,
        provider: "stripe",
        provider_mode: "test",
        status: status,
        amount_cents: 1_000,
        currency: "CNY",
        provider_payment_id: provider_payment_id,
        metadata: metadata,
        created_at: created_at,
        updated_at: created_at
      )
      [ order, payment ]
    end

    def payment_item(payment, reference:, status: "succeeded",
                     amount_cents: payment.amount_cents)
      {
        reference: reference,
        status: status,
        amount_cents: amount_cents,
        currency: payment.currency,
        local_payment_record_id: payment.id,
        local_order_public_id: payment.order.public_id,
        metadata_valid: true
      }
    end

    def refund_item(refund, reference:, payment_reference: nil, status: "succeeded")
      {
        reference: reference,
        payment_reference: payment_reference || refund.payment_record.metadata[
          "stripe_payment_intent_id"
        ].presence || refund.payment_record.provider_payment_id,
        status: status,
        amount_cents: refund.amount_cents,
        currency: refund.payment_record.currency,
        local_refund_id: refund.id,
        local_payment_record_id: refund.payment_record_id,
        local_order_public_id: refund.order.public_id,
        metadata_valid: true
      }
    end

    def reference_digest(reference)
      Digest::SHA256.hexdigest("stripe\0test\0#{reference}")
    end
  end
end
