# frozen_string_literal: true

require "test_helper"

module Commerce
  class PrepareOrderPaymentTest < ActiveSupport::TestCase
    setup do
      @order = build_order(status: "pending")
    end

    test "reuses the identical active attempt and blocks a provider change" do
      first = prepare(provider: "stripe", provider_mode: "test")
      replay = prepare(provider: "stripe", provider_mode: "test")
      change = prepare(provider: "fake")

      assert_predicate first, :success?, first.error
      assert_predicate replay, :success?, replay.error
      assert_equal first.value.id, replay.value.id
      assert_predicate change, :failure?
      assert_equal I18n.t("mcweb.services.errors.payment_attempt_already_active"), change.error
      assert_equal [ first.value.id ], @order.payment_records.where(status: %w[pending processing]).pluck(:id)
      assert_equal "stripe", first.value.reload.provider
    end

    test "active-attempt guidance is localized in both supported locales" do
      prepare(provider: "stripe", provider_mode: "test")

      I18n.with_locale(:en) do
        assert_includes prepare(provider: "fake").error, "payment session"
      end
      I18n.with_locale(:"zh-CN") do
        assert_includes prepare(provider: "fake").error, "支付会话"
      end
    end

    test "derives the payable amount from the freshly locked order" do
      ApplicationRecord.connection.execute(<<~SQL.squish)
        UPDATE store_orders
        SET subtotal_cents = 1350, total_cents = 1350
        WHERE id = #{@order.id}
      SQL
      assert_equal 1_200, @order.total_cents

      result = prepare(provider: "stripe", provider_mode: "test")

      assert_predicate result, :success?, result.error
      assert_equal 1_350, result.value.amount_cents
    end

    private

    def prepare(provider:, provider_mode: nil)
      Commerce::PrepareOrderPayment.call(
        order: @order,
        provider: provider,
        provider_mode: provider_mode
      )
    end

    def build_order(status:)
      suffix = SecureRandom.hex(6)
      Commerce::Order.create!(
        public_id: "ord_prepare_payment_#{suffix}",
        order_number: "PREP-#{suffix.upcase}",
        user: create_user,
        status: status,
        subtotal_cents: 1_200,
        discount_cents: 0,
        total_cents: 1_200,
        currency: "CNY"
      )
    end
  end

  class PrepareOrderPaymentConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    setup do
      @user = create_user
      suffix = SecureRandom.hex(6)
      @order = Commerce::Order.create!(
        public_id: "ord_prepare_concurrent_#{suffix}",
        order_number: "PREP-CON-#{suffix.upcase}",
        user: @user,
        status: "pending",
        subtotal_cents: 1_400,
        discount_cents: 0,
        total_cents: 1_400,
        currency: "CNY"
      )
    end

    teardown do
      Commerce::OrderEvent.where(store_order_id: @order&.id).delete_all
      Payments::Record.where(store_order_id: @order&.id).delete_all
      Commerce::Order.where(id: @order&.id).delete_all
      Notification.where(user_id: @user&.id).delete_all
      UserRole.where(user_id: @user&.id).delete_all
      User.where(id: @user&.id).destroy_all
    end

    test "overlapping preparations wait on the same order lock and create one active attempt" do
      connection = ApplicationRecord.connection
      main_pid = connection.select_value("SELECT pg_backend_pid()").to_i
      results = Queue.new
      pids = Queue.new
      transaction_open = false
      workers = []

      connection.execute("BEGIN")
      transaction_open = true
      connection.execute("SELECT id FROM store_orders WHERE id = #{@order.id} FOR UPDATE")

      2.times do
        workers << in_thread(results, pids) do
          Commerce::PrepareOrderPayment.call(
            order: Commerce::Order.find(@order.id),
            provider: "stripe",
            provider_mode: "test"
          )
        end
      end

      worker_pids = 2.times.map { pids.pop }
      worker_pids.each { |pid| refute_equal main_pid, pid }
      directly_waiting = Timeout.timeout(5) do
        loop do
          found = worker_pids.find { |pid| blocking_pids(pid).include?(main_pid) }
          break found if found

          sleep 0.02
        end
      end
      queued_waiter = (worker_pids - [ directly_waiting ]).sole
      assert_waiting_on!(waiting_pid: directly_waiting, blocking_pid: main_pid)
      assert_waiting_on!(waiting_pid: queued_waiter, blocking_pid: directly_waiting)

      connection.execute("COMMIT")
      transaction_open = false
      workers.each { |worker| assert worker.join(10), "payment preparation thread did not finish" }

      prepared = 2.times.map { results.pop }
      assert prepared.all? { |result| result.is_a?(ServiceResult) && result.success? }, prepared.inspect
      assert_equal 1, prepared.map { |result| result.value.id }.uniq.size
      assert_equal 1, @order.payment_records.where(status: %w[pending processing]).count
    ensure
      connection.execute("ROLLBACK") if transaction_open
      workers.each { |worker| worker.join(10) }
    end

    private

    def in_thread(result_queue, pid_queue, &block)
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          connection = ApplicationRecord.connection
          connection.execute("SET lock_timeout TO '10s'")
          pid_queue << connection.select_value("SELECT pg_backend_pid()").to_i
          result_queue << block.call
        rescue StandardError => error
          result_queue << error
        ensure
          connection.execute("SET lock_timeout TO DEFAULT")
        end
      end
    end

    def assert_waiting_on!(waiting_pid:, blocking_pid:)
      Timeout.timeout(5) do
        loop do
          blocked = ApplicationRecord.connection.uncached do
            ApplicationRecord.connection.select_value(<<~SQL.squish).to_i
              SELECT CASE
                WHEN #{Integer(blocking_pid)} = ANY(pg_blocking_pids(#{Integer(waiting_pid)})) THEN 1
                ELSE 0
              END
            SQL
          end
          break if blocked == 1

          sleep 0.02
        end
      end
    rescue Timeout::Error
      activity = ApplicationRecord.connection.select_rows(<<~SQL.squish)
        SELECT pid, state, wait_event_type, wait_event, pg_blocking_pids(pid), query
        FROM pg_stat_activity
        WHERE pid IN (#{Integer(waiting_pid)}, #{Integer(blocking_pid)})
        ORDER BY pid
      SQL
      flunk "expected backend #{waiting_pid} to wait on backend #{blocking_pid}; activity=#{activity.inspect}"
    end

    def blocking_pids(pid)
      ApplicationRecord.connection.uncached do
        value = ApplicationRecord.connection.select_value(<<~SQL.squish)
          SELECT pg_blocking_pids(#{Integer(pid)})::text
        SQL
        value.to_s.scan(/\d+/).map(&:to_i)
      end
    end
  end

  class CancelConfirmPaymentLockOrderTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    setup do
      @user = create_user
      suffix = SecureRandom.hex(6)
      @order = Commerce::Order.create!(
        public_id: "ord_cancel_confirm_#{suffix}",
        order_number: "CAN-CON-#{suffix.upcase}",
        user: @user,
        status: "awaiting_payment",
        subtotal_cents: 1_600,
        discount_cents: 0,
        total_cents: 1_600,
        currency: "CNY"
      )
      @payment = Payments::Record.create!(
        order: @order,
        provider: "stripe",
        provider_mode: "test",
        provider_payment_id: "cs_test_cancel_confirm_#{SecureRandom.hex(8)}",
        status: "pending",
        amount_cents: @order.total_cents,
        currency: @order.currency
      )
      @event = verified_success_event
    end

    teardown do
      Payments::LatePaymentCase.where(payment_record_id: @payment&.id).delete_all
      Payments::WebhookEvent.where(id: @event&.id).delete_all
      Commerce::OrderEvent.where(store_order_id: @order&.id).delete_all
      Payments::Record.where(id: @payment&.id).delete_all
      Commerce::Order.where(id: @order&.id).delete_all
      Notification.where(user_id: @user&.id).delete_all
      UserRole.where(user_id: @user&.id).delete_all
      User.where(id: @user&.id).destroy_all
    end

    test "wait graph proves cancellation and confirmation both lock order before payment" do
      connection = ApplicationRecord.connection
      main_pid = connection.select_value("SELECT pg_backend_pid()").to_i
      cancellation_results = Queue.new
      cancellation_pids = Queue.new
      confirmation_results = Queue.new
      confirmation_pids = Queue.new
      transaction_open = false
      cancellation = nil
      confirmation = nil

      connection.execute("BEGIN")
      transaction_open = true
      connection.execute("SELECT id FROM payment_records WHERE id = #{@payment.id} FOR UPDATE")

      cancellation = in_thread(cancellation_results, cancellation_pids) do
        Commerce::CancelOrder.call(order: Commerce::Order.find(@order.id), actor: User.find(@user.id))
      end
      cancellation_pid = cancellation_pids.pop
      assert_waiting_on!(waiting_pid: cancellation_pid, blocking_pid: main_pid)

      confirmation = in_thread(confirmation_results, confirmation_pids) do
        Commerce::ConfirmPayment.call(
          payment_record: Payments::Record.find(@payment.id),
          provider_payment_id: @payment.provider_payment_id,
          metadata: { "webhook_event_id" => @event.event_id },
          webhook_event: Payments::WebhookEvent.find(@event.id)
        )
      end
      confirmation_pid = confirmation_pids.pop
      assert_waiting_on!(waiting_pid: confirmation_pid, blocking_pid: cancellation_pid)

      connection.execute("COMMIT")
      transaction_open = false
      assert cancellation.join(10), "cancellation thread did not finish"
      assert confirmation.join(10), "confirmation thread did not finish"

      cancellation_result = cancellation_results.pop
      confirmation_result = confirmation_results.pop
      assert_instance_of ServiceResult, cancellation_result
      assert_predicate cancellation_result, :success?, cancellation_result.error
      assert_instance_of ServiceResult, confirmation_result
      assert_predicate confirmation_result, :failure?
      assert confirmation_result.value[:orphaned]
      assert_equal "cancelled", @order.reload.status
      assert_equal "succeeded", @payment.reload.status
      assert_equal "order_cancelled", @payment.metadata["orphan_reason"]
      assert_equal @payment, Payments::LatePaymentCase.sole.payment_record
    ensure
      connection.execute("ROLLBACK") if transaction_open
      cancellation&.join(10)
      confirmation&.join(10)
    end

    private

    def verified_success_event
      payload = {
        "type" => "checkout.session.completed",
        "data" => {
          "object" => {
            "id" => @payment.provider_payment_id,
            "object" => "checkout.session",
            "livemode" => false,
            "payment_status" => "paid",
            "amount_total" => @payment.amount_cents,
            "currency" => @payment.currency.downcase,
            "client_reference_id" => @order.public_id,
            "metadata" => {
              "payment_record_id" => @payment.id.to_s,
              "order_public_id" => @order.public_id
            }
          }
        }
      }
      Payments::WebhookEvent.create!(
        provider: "stripe",
        event_id: "evt_cancel_confirm_#{SecureRandom.hex(8)}",
        event_type: "checkout.session.completed",
        status: "received",
        payload: payload,
        payload_digest: Payments::WebhookPayload.digest(payload, event_type: "checkout.session.completed"),
        verified_at: Time.current
      )
    end

    def in_thread(result_queue, pid_queue, &block)
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          connection = ApplicationRecord.connection
          connection.execute("SET lock_timeout TO '10s'")
          pid_queue << connection.select_value("SELECT pg_backend_pid()").to_i
          result_queue << block.call
        rescue StandardError => error
          result_queue << error
        ensure
          connection.execute("SET lock_timeout TO DEFAULT")
        end
      end
    end

    def assert_waiting_on!(waiting_pid:, blocking_pid:)
      Timeout.timeout(5) do
        loop do
          blocked = ApplicationRecord.connection.uncached do
            ApplicationRecord.connection.select_value(<<~SQL.squish).to_i
              SELECT CASE
                WHEN #{Integer(blocking_pid)} = ANY(pg_blocking_pids(#{Integer(waiting_pid)})) THEN 1
                ELSE 0
              END
            SQL
          end
          break if blocked == 1

          sleep 0.02
        end
      end
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
