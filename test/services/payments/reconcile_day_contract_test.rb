# frozen_string_literal: true

require "test_helper"

module Payments
  class ReconcileDayContractTest < ActiveSupport::TestCase
    class StaticAdapter
      def initialize(payments: [], refunds: [])
        @payments = payments
        @refunds = refunds
      end

      def payment_page(window_start:, window_end:, cursor: nil)
        page(@payments, window_start, window_end, cursor)
      end

      def refund_page(window_start:, window_end:, cursor: nil)
        page(@refunds, window_start, window_end, cursor)
      end

      private

      def page(items, window_start, window_end, cursor)
        raise "unexpected reconciliation cursor" if cursor
        raise "invalid reconciliation window" unless window_end == window_start + 1.day

        ServiceResult.success(items: items, next_cursor: nil)
      end
    end

    setup do
      @date = Date.new(2026, 7, 20)
      @window_start = Time.utc(2026, 7, 20)
      @now = Time.utc(2026, 7, 29, 12)
      configure_stripe!
    end

    test "unknown but well formed provider statuses produce payment and refund mismatches" do
      order, payment = create_payment(
        suffix: "unknown",
        provider_payment_id: "pi_unknown_status"
      )
      refund = Commerce::Refund.create!(
        order: order,
        payment_record: payment,
        status: "completed",
        amount_cents: 300,
        provider_refund_id: "re_unknown_status",
        created_at: @window_start + 3.hours,
        updated_at: @window_start + 3.hours
      )
      adapter = StaticAdapter.new(
        payments: [
          payment_item(
            payment,
            status: "future_payment_state"
          )
        ],
        refunds: [
          refund_item(
            refund,
            status: "future_refund_state"
          )
        ]
      )

      result = reconcile(adapter: adapter)

      assert result.success?
      discrepancies = result.value[:run].discrepancies
      payment_mismatch = discrepancies.find_by!(kind: "payment_status_mismatch")
      refund_mismatch = discrepancies.find_by!(kind: "refund_status_mismatch")
      assert_equal "future_payment_state", payment_mismatch.provider_status
      assert_equal "succeeded", payment_mismatch.local_status
      assert_equal "future_refund_state", refund_mismatch.provider_status
      assert_equal "completed", refund_mismatch.local_status
      assert_equal 2, discrepancies.count
    end

    test "refund payment intent drift is reported against the matched local refund" do
      order, payment = create_payment(
        suffix: "refund_owner",
        provider_payment_id: "pi_refund_owner"
      )
      refund = Commerce::Refund.create!(
        order: order,
        payment_record: payment,
        status: "completed",
        amount_cents: 300,
        provider_refund_id: "re_refund_owner",
        created_at: @window_start + 3.hours,
        updated_at: @window_start + 3.hours
      )
      adapter = StaticAdapter.new(
        payments: [ payment_item(payment) ],
        refunds: [
          refund_item(refund).merge(
            payment_reference: "pi_different_payment_owner"
          )
        ]
      )

      result = reconcile(adapter: adapter)

      assert result.success?
      discrepancies = result.value[:run].discrepancies
      assert_equal [ "refund_payment_mismatch" ], discrepancies.pluck(:kind)
      mismatch = discrepancies.sole
      assert_equal refund.id, mismatch.refund_id
      assert_equal payment.id, mismatch.payment_record_id
      assert_equal order.id, mismatch.store_order_id
      assert_equal "re_••••wner", mismatch.reference_masked
    end

    test "order amount and currency drift are distinct from a matching local payment" do
      order, payment = create_payment(
        suffix: "order_drift",
        provider_payment_id: "pi_order_drift"
      )
      order.update!(total_cents: 1_200, currency: "USD")

      result = reconcile(
        adapter: StaticAdapter.new(payments: [ payment_item(payment) ])
      )

      assert result.success?
      discrepancies = result.value[:run].discrepancies
      assert_equal %w[order_amount_mismatch order_currency_mismatch],
        discrepancies.order(:kind).pluck(:kind)
      refute discrepancies.exists?(kind: "payment_amount_mismatch")
      refute discrepancies.exists?(kind: "payment_currency_mismatch")
      discrepancies.each do |discrepancy|
        assert_equal payment.id, discrepancy.payment_record_id
        assert_equal order.id, discrepancy.store_order_id
        assert_equal 1_200, discrepancy.local_amount_cents
        assert_equal 1_000, discrepancy.provider_amount_cents
        assert_equal "USD", discrepancy.local_currency
        assert_equal "CNY", discrepancy.provider_currency
      end
    end

    test "refresh replaces stale amount currency and status snapshots for one reference" do
      amount_payment = create_payment(
        suffix: "amount",
        provider_payment_id: "pi_snapshot_amount"
      ).last
      currency_payment = create_payment(
        suffix: "currency",
        provider_payment_id: "pi_snapshot_currency"
      ).last
      status_payment = create_payment(
        suffix: "status",
        provider_payment_id: "pi_snapshot_status"
      ).last

      first = reconcile(
        adapter: StaticAdapter.new(
          payments: [
            payment_item(amount_payment, amount_cents: 1_200),
            payment_item(currency_payment, currency: "USD"),
            payment_item(status_payment, status: "future_state_one")
          ]
        )
      )
      assert first.success?
      run = first.value[:run]
      assert_equal 5, run.discrepancies.open.count

      @now += 1.minute
      second = reconcile(
        adapter: StaticAdapter.new(
          payments: [
            payment_item(amount_payment, amount_cents: 1_300),
            payment_item(currency_payment, currency: "EUR"),
            payment_item(status_payment, status: "future_state_two")
          ]
        ),
        refresh: true
      )

      assert second.success?
      run = second.value[:run]
      assert_equal 10, run.discrepancies.count
      assert_equal 5, run.discrepancies.open.count
      assert_equal 5, run.discrepancies.resolved.count

      assert_snapshot_rotated(
        run,
        kind: "payment_amount_mismatch",
        attribute: :provider_amount_cents,
        previous: 1_200,
        current: 1_300
      )
      assert_snapshot_rotated(
        run,
        kind: "payment_currency_mismatch",
        attribute: :provider_currency,
        previous: "USD",
        current: "EUR"
      )
      assert_snapshot_rotated(
        run,
        kind: "payment_status_mismatch",
        attribute: :provider_status,
        previous: "future_state_one",
        current: "future_state_two"
      )
      assert_snapshot_rotated(
        run,
        kind: "order_amount_mismatch",
        attribute: :provider_amount_cents,
        previous: 1_200,
        current: 1_300
      )
      assert_snapshot_rotated(
        run,
        kind: "order_currency_mismatch",
        attribute: :provider_currency,
        previous: "USD",
        current: "EUR"
      )

      visible = Payments::ReconciliationDiscrepanciesQuery.new(
        status: "open"
      ).relation.where(run_id: run.id)
      assert_equal 5, visible.count
      serialized = visible.map do |discrepancy|
        Payments::ReconciliationSerializer.discrepancy(discrepancy)
      end.index_by { |row| row[:kind] }
      assert_equal 1_300,
        serialized.fetch("payment_amount_mismatch")[:provider_amount_cents]
      assert_equal "EUR",
        serialized.fetch("payment_currency_mismatch")[:provider_currency]
      assert_equal "future_state_two",
        serialized.fetch("payment_status_mismatch")[:provider_status]
      assert_equal 1_300,
        serialized.fetch("order_amount_mismatch")[:provider_amount_cents]
      assert_equal "EUR",
        serialized.fetch("order_currency_mismatch")[:provider_currency]
    end

    test "test reconciliation neither scans nor binds explicitly live local records" do
      order, live_payment = create_payment(
        suffix: "live_mode",
        provider_payment_id: "pi_live_local_record",
        livemode: true
      )
      live_refund = Commerce::Refund.create!(
        order: order,
        payment_record: live_payment,
        status: "completed",
        amount_cents: 300,
        provider_refund_id: "re_live_local_record",
        provider_metadata: { "stripe_livemode" => true },
        created_at: @window_start + 3.hours,
        updated_at: @window_start + 3.hours
      )

      local_scan = reconcile(adapter: StaticAdapter.new)

      assert local_scan.success?
      assert_empty local_scan.value[:run].discrepancies

      @now += 1.minute
      remote_metadata = reconcile(
        adapter: StaticAdapter.new(
          payments: [ payment_item(live_payment) ],
          refunds: [ refund_item(live_refund) ]
        ),
        refresh: true
      )

      assert remote_metadata.success?
      discrepancies = remote_metadata.value[:run].discrepancies.open
      assert_equal %w[payment_metadata_mismatch refund_metadata_mismatch],
        discrepancies.order(:kind).pluck(:kind)
      discrepancies.each do |discrepancy|
        assert_nil discrepancy.payment_record_id
        assert_nil discrepancy.refund_id
        assert_nil discrepancy.store_order_id
      end
      refute discrepancies.where(
        kind: %w[
          payment_amount_mismatch
          payment_currency_mismatch
          payment_status_mismatch
          refund_amount_mismatch
          refund_currency_mismatch
          refund_status_mismatch
        ]
      ).exists?
    end

    test "live reconciliation neither scans nor binds explicitly test local records" do
      configure_stripe!(mode: "live")
      order, test_payment = create_payment(
        suffix: "test_mode",
        provider_payment_id: "pi_test_local_record",
        livemode: false
      )
      test_refund = Commerce::Refund.create!(
        order: order,
        payment_record: test_payment,
        status: "completed",
        amount_cents: 300,
        provider_refund_id: "re_test_local_record",
        provider_metadata: { "stripe_livemode" => false },
        created_at: @window_start + 3.hours,
        updated_at: @window_start + 3.hours
      )

      local_scan = reconcile(adapter: StaticAdapter.new)

      assert local_scan.success?
      assert_equal "live", local_scan.value[:run].mode
      assert_empty local_scan.value[:run].discrepancies

      @now += 1.minute
      remote_metadata = reconcile(
        adapter: StaticAdapter.new(
          payments: [ payment_item(test_payment) ],
          refunds: [ refund_item(test_refund) ]
        ),
        refresh: true
      )

      assert remote_metadata.success?
      discrepancies = remote_metadata.value[:run].discrepancies.open
      assert_equal %w[payment_metadata_mismatch refund_metadata_mismatch],
        discrepancies.order(:kind).pluck(:kind)
      assert discrepancies.all? { |discrepancy|
        discrepancy.payment_record_id.nil? &&
          discrepancy.refund_id.nil? &&
          discrepancy.store_order_id.nil?
      }
    end

    test "refresh keeps persistent local missing references open and touches last seen" do
      order, payment = create_payment(
        suffix: "missing_reference",
        provider_payment_id: nil
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

      first = reconcile(adapter: StaticAdapter.new)

      assert first.success?
      run = first.value[:run]
      payment_missing = run.discrepancies.find_by!(
        kind: "payment_reference_missing"
      )
      refund_missing = run.discrepancies.find_by!(
        kind: "refund_reference_missing"
      )
      assert payment_missing.open?
      assert refund_missing.open?
      first_seen = {
        payment: payment_missing.last_seen_at,
        refund: refund_missing.last_seen_at
      }

      @now += 1.minute
      second = reconcile(adapter: StaticAdapter.new, refresh: true)

      assert second.success?
      assert payment_missing.reload.open?
      assert refund_missing.reload.open?
      assert_operator payment_missing.last_seen_at, :>, first_seen.fetch(:payment)
      assert_operator refund_missing.last_seen_at, :>, first_seen.fetch(:refund)
      assert_equal 1, run.discrepancies.where(
        kind: "payment_reference_missing"
      ).count
      assert_equal 1, run.discrepancies.where(
        kind: "refund_reference_missing"
      ).count
    end

    test "refresh rotates changed local snapshots that still have no references" do
      order, payment = create_payment(
        suffix: "changed_missing_reference",
        provider_payment_id: nil
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

      first = reconcile(adapter: StaticAdapter.new)

      assert first.success?
      run = first.value[:run]
      assert_equal 2, run.discrepancies.open.count
      payment.update!(
        status: "processing",
        amount_cents: 1_100,
        currency: "USD"
      )
      refund.update!(status: "approved", amount_cents: 350)

      @now += 1.minute
      second = reconcile(adapter: StaticAdapter.new, refresh: true)

      assert second.success?
      assert_equal 4, run.discrepancies.count
      assert_equal 2, run.discrepancies.open.count
      assert_equal 2, run.discrepancies.resolved.count

      payment_rows = run.discrepancies.where(
        kind: "payment_reference_missing"
      )
      assert_equal 2, payment_rows.count
      old_payment = payment_rows.find_by!(status: "resolved")
      current_payment = payment_rows.find_by!(status: "open")
      assert_equal [ "succeeded", 1_000, "CNY" ],
        old_payment.values_at(:local_status, :local_amount_cents, :local_currency)
      assert_equal [ "processing", 1_100, "USD" ],
        current_payment.values_at(
          :local_status,
          :local_amount_cents,
          :local_currency
        )

      refund_rows = run.discrepancies.where(kind: "refund_reference_missing")
      assert_equal 2, refund_rows.count
      old_refund = refund_rows.find_by!(status: "resolved")
      current_refund = refund_rows.find_by!(status: "open")
      assert_equal [ "completed", 300, "CNY" ],
        old_refund.values_at(:local_status, :local_amount_cents, :local_currency)
      assert_equal [ "approved", 350, "USD" ],
        current_refund.values_at(
          :local_status,
          :local_amount_cents,
          :local_currency
        )
      assert_operator current_payment.first_seen_at, :>, old_payment.first_seen_at
      assert_operator current_refund.first_seen_at, :>, old_refund.first_seen_at
    end

    test "current remote missing references prevent synthetic duplicates beside reviewed history" do
      order, payment = create_payment(
        suffix: "reviewed_missing_reference",
        provider_payment_id: nil
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
      first = reconcile(adapter: StaticAdapter.new)
      assert first.success?
      run = first.value[:run]
      reviewer = create_user
      historical_payment = run.discrepancies.find_by!(
        kind: "payment_reference_missing"
      )
      historical_refund = run.discrepancies.find_by!(
        kind: "refund_reference_missing"
      )
      historical_payment.update!(
        status: "acknowledged",
        reviewed_by: reviewer,
        reviewed_at: @now,
        review_note: "Historical payment reference reviewed."
      )
      historical_refund.update!(
        status: "ignored",
        reviewed_by: reviewer,
        reviewed_at: @now,
        review_note: "Historical refund reference reviewed."
      )

      @now += 1.minute
      second = reconcile(
        adapter: StaticAdapter.new(
          payments: [
            payment_item(payment).merge(reference: "pi_actual_missing_reference")
          ],
          refunds: [
            refund_item(refund).merge(
              reference: "re_actual_missing_reference",
              payment_reference: "pi_actual_missing_reference"
            )
          ]
        ),
        refresh: true
      )

      assert second.success?
      payment_rows = run.discrepancies.where(
        kind: "payment_reference_missing"
      )
      refund_rows = run.discrepancies.where(kind: "refund_reference_missing")
      assert_equal 2, payment_rows.count
      assert_equal 2, refund_rows.count
      assert_equal 1, payment_rows.where(reference_masked: nil).count
      assert_equal 1, refund_rows.where(reference_masked: nil).count

      assert historical_payment.reload.acknowledged?
      assert historical_refund.reload.ignored?
      current_payment = payment_rows.find_by!(status: "open")
      current_refund = refund_rows.find_by!(status: "open")
      assert_equal "pi_••••ence", current_payment.reference_masked
      assert_equal "re_••••ence", current_refund.reference_masked
      assert_equal @now, current_payment.last_seen_at
      assert_equal @now, current_refund.last_seen_at
      assert_operator current_payment.last_seen_at, :>,
        historical_payment.last_seen_at
      assert_operator current_refund.last_seen_at, :>,
        historical_refund.last_seen_at
    end

    test "unknown local Stripe mode is quarantined from local and remote matching" do
      order, payment = create_payment(
        suffix: "unknown_environment",
        provider_payment_id: "pi_unknown_environment",
        livemode: nil
      )
      refund = Commerce::Refund.create!(
        order: order,
        payment_record: payment,
        status: "completed",
        amount_cents: 300,
        provider_refund_id: "re_unknown_environment",
        created_at: @window_start + 3.hours,
        updated_at: @window_start + 3.hours
      )
      assert_nil payment.provider_mode

      first = reconcile(adapter: StaticAdapter.new)

      assert first.success?
      run = first.value[:run]
      assert_equal %w[payment_environment_unknown refund_environment_unknown],
        run.discrepancies.order(:kind).pluck(:kind)
      refute run.discrepancies.where(
        kind: %w[
          local_payment_missing_provider
          local_refund_missing_provider
        ]
      ).exists?

      @now += 1.minute
      second = reconcile(
        adapter: StaticAdapter.new(
          payments: [ payment_item(payment) ],
          refunds: [ refund_item(refund) ]
        ),
        refresh: true
      )

      assert second.success?
      assert_equal %w[payment_metadata_mismatch refund_metadata_mismatch],
        run.discrepancies.where(status: "open")
          .where(kind: %w[payment_metadata_mismatch refund_metadata_mismatch])
          .order(:kind)
          .pluck(:kind)
      run.discrepancies.where(
        kind: %w[payment_metadata_mismatch refund_metadata_mismatch]
      ).each do |discrepancy|
        assert_nil discrepancy.payment_record_id
        assert_nil discrepancy.refund_id
        assert_nil discrepancy.store_order_id
      end
      refute run.discrepancies.where(
        kind: %w[
          local_payment_missing_provider
          local_refund_missing_provider
          provider_payment_missing_local
          provider_refund_missing_local
        ]
      ).exists?
    end

    private

    def configure_stripe!(mode: "test")
      config = Payments::ProviderConfig.find_or_initialize_by(provider: "stripe")
      config.assign_attributes(
        enabled: true,
        mode: mode,
        credentials: {
          "secret_key" => "sk_#{mode}_reconciliation_contract",
          "webhook_secret" => "whsec_reconciliation_contract"
        }
      )
      config.save!
      mark_stripe_provider_connection_tested!(config)
    end

    def create_payment(suffix:, provider_payment_id:, livemode: false)
      customer = create_user
      order = Commerce::Order.create!(
        public_id: "ord_recon_contract_#{suffix}_#{SecureRandom.hex(4)}",
        order_number: "RECON-CONTRACT-#{suffix.upcase}-#{SecureRandom.hex(3).upcase}",
        user: customer,
        status: "paid",
        subtotal_cents: 1_000,
        discount_cents: 0,
        total_cents: 1_000,
        currency: "CNY",
        created_at: @window_start + 2.hours,
        updated_at: @window_start + 2.hours
      )
      payment = Payments::Record.create!(
        order: order,
        provider: "stripe",
        status: "succeeded",
        amount_cents: 1_000,
        currency: "CNY",
        provider_payment_id: provider_payment_id,
        metadata: {
          "stripe_payment_intent_id" => provider_payment_id,
          "stripe_checkout_livemode" => livemode,
          "stripe_livemode" => livemode
        },
        created_at: @window_start + 2.hours,
        updated_at: @window_start + 2.hours
      )

      [ order, payment ]
    end

    def payment_item(payment, status: "succeeded",
                     amount_cents: payment.amount_cents,
                     currency: payment.currency)
      {
        reference: payment.provider_payment_id,
        status: status,
        amount_cents: amount_cents,
        currency: currency,
        local_payment_record_id: payment.id,
        local_order_public_id: payment.order.public_id,
        metadata_valid: true
      }
    end

    def refund_item(refund, status: "succeeded")
      {
        reference: refund.provider_refund_id,
        payment_reference: refund.payment_record.provider_payment_id,
        status: status,
        amount_cents: refund.amount_cents,
        currency: refund.payment_record.currency,
        local_refund_id: refund.id,
        local_payment_record_id: refund.payment_record_id,
        local_order_public_id: refund.order.public_id,
        metadata_valid: true
      }
    end

    def reconcile(adapter:, refresh: false)
      Payments::ReconcileDay.call(
        date: @date,
        adapter: adapter,
        refresh: refresh,
        clock: -> { @now }
      )
    end

    def assert_snapshot_rotated(run, kind:, attribute:, previous:, current:)
      discrepancies = run.discrepancies.where(kind: kind).order(:first_seen_at)
      assert_equal 2, discrepancies.count
      stale = discrepancies.find_by!(status: "resolved")
      active = discrepancies.find_by!(status: "open")
      assert_equal previous, stale.public_send(attribute)
      assert_equal current, active.public_send(attribute)
      assert_operator active.first_seen_at, :>, stale.first_seen_at
    end
  end
end
