# frozen_string_literal: true

require "test_helper"
require "timeout"

module Commerce
  class RefundProviderQuarantineTest < ActiveSupport::TestCase
    class ResultProvider
      attr_reader :calls

      def initialize(result)
        @result = result
        @calls = 0
      end

      def process_refund(_refund)
        @calls += 1
        @result
      end
    end

    class TimeoutProvider
      attr_reader :calls

      def initialize
        @calls = 0
      end

      def process_refund(_refund)
        @calls += 1
        raise Timeout::Error, "provider response timed out"
      end
    end

    setup do
      @user = create_user
      @admin = create_user
      @order = Commerce::Order.create!(
        public_id: "ord_refund_quarantine_#{SecureRandom.hex(5)}",
        order_number: "RFQ#{SecureRandom.hex(5).upcase}",
        user: @user,
        status: "paid",
        subtotal_cents: 1_000,
        total_cents: 1_000,
        currency: "CNY"
      )
      @payment = Payments::Record.create!(
        order: @order,
        provider: "fake",
        provider_payment_id: "refund_quarantine_#{SecureRandom.hex(8)}",
        status: "succeeded",
        amount_cents: 1_000,
        currency: "CNY"
      )
      @refund = Commerce::Refund.create!(
        order: @order,
        payment_record: @payment,
        requested_by: @user,
        requested_by_customer: true,
        status: "pending",
        amount_cents: 700
      )
      enable_refund_window!
      anchor_order_payment_at!(@order)
    end

    test "a succeeded provider response mismatch is quarantined and cannot be requested or processed twice" do
      provider = ResultProvider.new(
        ServiceResult.failure(
          error: :stripe_refund_response_does_not_match_the_local_refund,
          code: "provider_mismatch",
          value: {
            provider_refund_id: "re_remote_succeeded",
            provider_status: "succeeded",
            provider_metadata: { "remote_request_id" => "req_mismatch" }
          }
        )
      )

      first = with_provider(provider) { process_refund }
      replay = with_provider(provider) { process_refund }
      second_request = Commerce::RequestRefund.call(
        order: @order,
        user: @user,
        amount_cents: 100
      )

      assert_predicate first, :failure?
      assert_equal "refund_provider_outcome_unknown", first.code
      assert_equal I18n.t("mcweb.services.errors.refund_provider_outcome_unknown"), first.error
      assert_predicate replay, :failure?
      assert_equal "refund_no_longer_valid", replay.code
      assert_predicate second_request, :failure?
      assert_equal "refund_reconciliation_required", second_request.code
      assert_equal 1, provider.calls

      @refund.reload
      assert_predicate @refund, :provider_unknown?
      assert_equal "re_remote_succeeded", @refund.provider_refund_id
      assert_equal "succeeded", @refund.provider_status
      assert_equal "provider_mismatch", @refund.provider_error_code
      assert_equal "req_mismatch", @refund.provider_metadata["remote_request_id"]
      assert_equal "unknown", @refund.provider_metadata["outcome_classification"]
      assert_equal 700, @payment.refunds.reserved.sum(:amount_cents)
      assert_equal 1, @order.events.where(event_type: "refund_provider_unknown").count

      second_admin_refund = Commerce::ProcessRefund.call(
        order: @order,
        payment_record: @payment,
        amount_cents: 100,
        approved_by: @admin
      )
      assert_predicate second_admin_refund, :failure?
      assert_equal "refund_reconciliation_required", second_admin_refund.code
      assert_equal 1, @payment.refunds.count
    end

    test "an ambiguous timeout is quarantined without releasing the reserved balance" do
      provider = TimeoutProvider.new

      result = with_provider(provider) { process_refund }
      replay = with_provider(provider) { process_refund }

      assert_predicate result, :failure?
      assert_equal "refund_provider_outcome_unknown", result.code
      assert_predicate replay, :failure?
      assert_equal "refund_no_longer_valid", replay.code
      assert_equal 1, provider.calls

      @refund.reload
      assert_predicate @refund, :provider_unknown?
      assert_equal "unknown", @refund.provider_status
      assert_equal "refund_provider_exception", @refund.provider_error_code
      assert_equal "Timeout::Error", @refund.provider_metadata["exception_class"]
      assert_equal 700, @payment.refunds.reserved.sum(:amount_cents)
    end

    test "one quarantined payment blocks refunds against every other payment on the order" do
      @refund.update!(status: :provider_unknown)
      second_payment = Payments::Record.create!(
        order: @order,
        provider: "stripe",
        provider_mode: "test",
        provider_payment_id: "cs_quarantine_other_#{SecureRandom.hex(8)}",
        status: "succeeded",
        amount_cents: @order.total_cents,
        currency: @order.currency
      )

      customer_result = Commerce::RequestRefund.call(
        order: @order,
        user: @user,
        amount_cents: 100
      )
      admin_result = Commerce::ProcessRefund.call(
        order: @order,
        payment_record: second_payment,
        amount_cents: 100,
        approved_by: @admin
      )

      assert_predicate customer_result, :failure?
      assert_equal "refund_reconciliation_required", customer_result.code
      assert_predicate admin_result, :failure?
      assert_equal "refund_reconciliation_required", admin_result.code
      assert_empty second_payment.refunds
    end

    test "an explicit provider failure is terminal and releases the reservation" do
      provider = ResultProvider.new(
        ServiceResult.failure(
          error: :stripe_refund_failed,
          code: "provider_refund_failed",
          value: {
            provider_refund_id: "re_remote_failed",
            provider_status: "failed",
            provider_error_code: "declined"
          }
        )
      )

      result = with_provider(provider) { process_refund }

      assert_predicate result, :failure?
      assert_equal "provider_refund_failed", result.code
      assert_predicate @refund.reload, :failed?
      assert_equal "declined", @refund.provider_error_code
      assert_equal 0, @payment.refunds.reserved.sum(:amount_cents)
    end

    test "quarantine labels and error messages exist in both supported locales" do
      [ :en, :"zh-CN" ].each do |locale|
        I18n.with_locale(locale) do
          refute_match(/translation missing/i, I18n.t("mcweb.services.errors.refund_provider_outcome_unknown"))
          refute_match(/translation missing/i, I18n.t("mcweb.services.errors.refund_reconciliation_required"))
          refute_match(/translation missing/i, I18n.t("mcweb.labels.refund_status.provider_unknown"))
          refute_match(/translation missing/i, I18n.t("mcweb.labels.order_events.refund_provider_unknown"))
        end
      end
    end

    private

    def process_refund
      Commerce::ProcessRefund.call(
        order: @order,
        payment_record: @payment,
        amount_cents: @refund.amount_cents,
        approved_by: @admin,
        existing_refund: @refund
      )
    end

    def with_provider(provider, &block)
      Payments::Provider.stub(:for, provider, &block)
    end
  end

  class RefundLockOrderConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    class BlockingPendingProvider
      attr_reader :entered, :release, :calls

      def initialize
        @entered = Queue.new
        @release = Queue.new
        @calls = 0
      end

      def process_refund(refund)
        @calls += 1
        @entered << refund.id
        @release.pop
        ServiceResult.failure(
          error: :stripe_refund_is_still_pending,
          code: "provider_pending",
          value: {
            provider_refund_id: "re_pending_#{refund.id}",
            provider_status: "pending"
          }
        )
      end
    end

    class PendingProvider
      attr_reader :calls

      def initialize
        @calls = 0
      end

      def process_refund(refund)
        @calls += 1
        ServiceResult.failure(
          error: :stripe_refund_is_still_pending,
          code: "provider_pending",
          value: {
            provider_refund_id: "re_pending_#{refund.id}",
            provider_status: "pending"
          }
        )
      end
    end

    setup do
      @user = create_user
      @admin = create_user
      @order = Commerce::Order.create!(
        public_id: "ord_refund_lock_#{SecureRandom.hex(5)}",
        order_number: "RFL#{SecureRandom.hex(5).upcase}",
        user: @user,
        status: "paid",
        subtotal_cents: 1_000,
        total_cents: 1_000,
        currency: "CNY"
      )
      @payment = Payments::Record.create!(
        order: @order,
        provider: "fake",
        provider_payment_id: "refund_lock_#{SecureRandom.hex(8)}",
        status: "succeeded",
        amount_cents: 1_000,
        currency: "CNY"
      )
      @refund = Commerce::Refund.create!(
        order: @order,
        payment_record: @payment,
        requested_by: @user,
        requested_by_customer: true,
        status: "pending",
        amount_cents: 500
      )
      @dispute = Commerce::Dispute.create!(
        order: @order,
        payment_record: @payment,
        provider: "fake",
        provider_dispute_id: "dp_refund_lock_#{SecureRandom.hex(8)}",
        status: "under_review",
        provider_status: "under_review",
        amount_cents: 300,
        liability_cents: 300,
        offset_cents: 0,
        currency: "CNY"
      )
    end

    teardown do
      Commerce::DisputeEvent.where(store_dispute_id: @dispute&.id).delete_all
      Commerce::DisputeRightsAction.where(store_dispute_id: @dispute&.id).delete_all
      Commerce::DisputeEvidence.where(store_dispute_id: @dispute&.id).delete_all
      Commerce::Dispute.where(id: @dispute&.id).delete_all
      Commerce::OrderEvent.where(store_order_id: @order&.id).delete_all
      Commerce::Refund.where(id: @refund&.id).delete_all
      Payments::Record.where(id: @payment&.id).delete_all
      Commerce::Order.where(id: @order&.id).delete_all
      Notification.where(user_id: [ @user&.id, @admin&.id ].compact).delete_all
      UserRole.where(user_id: [ @user&.id, @admin&.id ].compact).delete_all
      User.where(id: [ @user&.id, @admin&.id ].compact).destroy_all
    end

    test "approval processing rejection and withdrawal serialize without overwriting the approved refund" do
      provider = BlockingPendingProvider.new
      process_result = Queue.new

      Payments::Provider.stub(:for, provider) do
        processing = in_thread(process_result) { process_refund }
        provider.entered.pop
        assert_predicate @refund.reload, :approved?

        transition_results = Queue.new
        rejection = in_thread(transition_results) do
          Commerce::RejectRefund.call(
            refund: Commerce::Refund.find(@refund.id),
            actor: User.find(@admin.id),
            reason: "reject while processing"
          )
        end
        withdrawal = in_thread(transition_results) do
          Commerce::WithdrawRefund.call(
            order: Commerce::Order.find(@order.id),
            refund: Commerce::Refund.find(@refund.id),
            user: User.find(@user.id)
          )
        end

        assert rejection.join(5), "refund rejection thread did not finish"
        assert withdrawal.join(5), "refund withdrawal thread did not finish"
        transitions = 2.times.map { transition_results.pop }
        assert transitions.all? { |result| result.is_a?(ServiceResult) && result.failure? },
          transitions.inspect

        provider.release << true
        assert processing.join(5), "refund processing thread did not finish"
      ensure
        provider.release << true if processing&.alive?
        processing&.join(5)
        rejection&.join(5)
        withdrawal&.join(5)
      end

      result = process_result.pop
      assert_instance_of ServiceResult, result
      assert_predicate result, :failure?
      assert_equal "provider_pending", result.code
      assert_predicate @refund.reload, :approved?
      assert_equal 1, provider.calls
      assert_equal 0, @order.events.where(event_type: %w[refund_rejected refund_withdrawn]).count
    end

    test "refund processing and dispute rebalancing share order then payment lock order" do
      provider = PendingProvider.new
      barrier_key = 810_000_000 + @refund.id
      barrier_ready = Queue.new
      rebalance_result = Queue.new
      refund_result = Queue.new
      connection = ApplicationRecord.connection
      connection.execute("SELECT pg_advisory_lock(#{barrier_key})")
      barrier_released = false

      rebalancing = nil
      processing = nil
      Payments::Provider.stub(:for, provider) do
        processing = in_thread(refund_result, advisory_barrier: [ barrier_key, barrier_ready ]) do
          process_refund
        end
        rebalancing = in_thread(rebalance_result, advisory_barrier: [ barrier_key, barrier_ready ]) do
          Commerce::Disputes::RebalanceExposure.call(
            payment_record: Payments::Record.find(@payment.id),
            trigger_idempotency: "refund-lock-order-#{@refund.id}"
          )
        end

        2.times { barrier_ready.pop }
        connection.execute("SELECT pg_advisory_unlock(#{barrier_key})")
        barrier_released = true

        assert processing.join(10), "refund processing thread did not finish"
        assert rebalancing.join(10), "dispute rebalance thread did not finish"
      ensure
        connection.execute("SELECT pg_advisory_unlock(#{barrier_key})") unless barrier_released
        processing&.join(10)
        rebalancing&.join(10)
      end

      processed = refund_result.pop
      rebalanced = rebalance_result.pop
      assert_instance_of ServiceResult, processed
      assert_predicate processed, :failure?, processed.error
      assert_equal "provider_pending", processed.code
      assert_instance_of ServiceResult, rebalanced
      assert_predicate rebalanced, :success?, rebalanced.error
      assert_equal 1, provider.calls
      assert_predicate @refund.reload, :approved?
      assert_equal 500, @payment.refunds.reserved.sum(:amount_cents)
      @dispute.reload
      assert_equal 300, @dispute.liability_cents
      assert_equal 0, @dispute.offset_cents
    end

    test "database wait graph proves refund and dispute work overlap in order then payment lock order" do
      provider = PendingProvider.new
      connection = ApplicationRecord.connection
      main_pid = connection.select_value("SELECT pg_backend_pid()").to_i
      refund_result = Queue.new
      refund_pid = Queue.new
      rebalance_result = Queue.new
      rebalance_pid = Queue.new
      transaction_open = false
      processing = nil
      rebalancing = nil

      Payments::Provider.stub(:for, provider) do
        connection.execute("BEGIN")
        transaction_open = true
        connection.execute("SELECT id FROM payment_records WHERE id = #{@payment.id} FOR UPDATE")

        processing = in_thread(refund_result, backend_pid_queue: refund_pid) { process_refund }
        processing_pid = refund_pid.pop
        refute_equal main_pid, processing_pid
        assert_waiting_on!(waiting_pid: processing_pid, blocking_pid: main_pid)

        rebalancing = in_thread(rebalance_result, backend_pid_queue: rebalance_pid) do
          Commerce::Disputes::RebalanceExposure.call(
            payment_record: Payments::Record.find(@payment.id),
            trigger_idempotency: "verified-lock-overlap-#{@refund.id}"
          )
        end
        rebalancing_backend_pid = rebalance_pid.pop
        assert_waiting_on!(waiting_pid: rebalancing_backend_pid, blocking_pid: processing_pid)

        connection.execute("COMMIT")
        transaction_open = false
        assert processing.join(10), "refund processing thread did not finish"
        assert rebalancing.join(10), "dispute rebalance thread did not finish"
      ensure
        connection.execute("ROLLBACK") if transaction_open
        processing&.join(10)
        rebalancing&.join(10)
      end

      processed = refund_result.pop
      rebalanced = rebalance_result.pop
      assert_instance_of ServiceResult, processed
      assert_predicate processed, :failure?
      assert_equal "provider_pending", processed.code
      assert_instance_of ServiceResult, rebalanced
      assert_predicate rebalanced, :success?, rebalanced.error
    end

    private

    def process_refund
      Commerce::ProcessRefund.call(
        order: Commerce::Order.find(@order.id),
        payment_record: Payments::Record.find(@payment.id),
        amount_cents: @refund.amount_cents,
        approved_by: User.find(@admin.id),
        existing_refund: Commerce::Refund.find(@refund.id)
      )
    end

    def in_thread(result_queue, advisory_barrier: nil, backend_pid_queue: nil, &block)
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          connection = ApplicationRecord.connection
          barrier_acquired = false
          connection.execute("SET lock_timeout TO '10s'")
          backend_pid_queue << connection.select_value("SELECT pg_backend_pid()").to_i if backend_pid_queue
          if advisory_barrier
            barrier_key, ready = advisory_barrier
            ready << true
            connection.execute("SELECT pg_advisory_lock_shared(#{Integer(barrier_key)})")
            barrier_acquired = true
          end
          result_queue << block.call
        rescue StandardError => error
          result_queue << error
        ensure
          if barrier_acquired
            connection.execute("SELECT pg_advisory_unlock_shared(#{Integer(barrier_key)})")
          end
          connection.execute("SET lock_timeout TO DEFAULT")
        end
      end
    end

    def assert_waiting_on!(waiting_pid:, blocking_pid:)
      blocked = Timeout.timeout(5) do
        loop do
          value = ApplicationRecord.connection.uncached do
            ApplicationRecord.connection.select_value(<<~SQL.squish)
              SELECT CASE
                WHEN #{Integer(blocking_pid)} = ANY(pg_blocking_pids(#{Integer(waiting_pid)})) THEN 1
                ELSE 0
              END
            SQL
          end
          break true if value.to_i == 1

          sleep 0.02
        end
      end
      assert blocked,
        "expected backend #{waiting_pid} to wait on backend #{blocking_pid}"
    rescue Timeout::Error
      activity = ApplicationRecord.connection.select_rows(<<~SQL.squish)
        SELECT pid, state, wait_event_type, wait_event, pg_blocking_pids(pid), query
        FROM pg_stat_activity
        WHERE pid IN (#{Integer(waiting_pid)}, #{Integer(blocking_pid)})
        ORDER BY pid
      SQL
      flunk "expected backend #{waiting_pid} to wait on backend #{blocking_pid}; activity=#{activity.inspect}"
    end
  end
end
