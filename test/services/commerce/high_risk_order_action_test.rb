# frozen_string_literal: true

require "test_helper"

module Commerce
  class HighRiskOrderActionTest < ActiveSupport::TestCase
    setup do
      @actor = create_user(account_type: "staff")
      @buyer = create_user
      @reason = "Manual payment operations case MC-771"
    end

    test "each manual order action requires its own permission" do
      order = create_order
      grant_permission(@actor, "store.orders.cancel")

      allowed = authorize(order_ids: [ order.public_id ], action: "cancel_pending")
      assert_predicate allowed, :success?, allowed.error

      %w[mark_paid mark_fulfilled].each do |action|
        denied = authorize(order_ids: [ order.public_id ], action: action)
        assert_predicate denied, :failure?
        assert_equal I18n.t("mcweb.services.errors.high_risk_unauthorized"), denied.error
      end
    end

    test "atomic bulk cancel creates one operation and one audit per target and replay is single effect" do
      grant_permission(@actor, "store.orders.cancel")
      first_order = create_order
      second_order = create_order
      request_id = SecureRandom.uuid
      authorization = authorize!(
        order_ids: [ first_order.public_id, second_order.public_id ],
        action: "cancel_pending",
        request_id: request_id
      )
      attributes = execute_attributes(
        order_ids: [ first_order.public_id, second_order.public_id ],
        action: "cancel_pending",
        request_id: request_id,
        authorization: authorization
      )

      result = nil
      assert_difference -> {
        Commerce::HighRiskOperation.where(request_id: request_id).count
      }, 1 do
        assert_difference -> {
          AuditLog.by_action("commerce.order_cancel")
            .where("metadata ->> 'request_id' = ?", request_id)
            .count
        }, 2 do
          result = Commerce::HighRiskOrderAction.call(**attributes)
        end
      end
      assert_predicate result, :success?, result.error
      assert_equal 2, result.value[:processed]
      assert first_order.reload.cancelled?
      assert second_order.reload.cancelled?

      assert_no_difference -> { Commerce::HighRiskOperation.where(request_id: request_id).count } do
        replay = Commerce::HighRiskOrderAction.call(**attributes)
        assert_predicate replay, :success?, replay.error
        assert replay.value[:idempotent]
      end
    end

    test "target status change makes whole bulk request fail without partial cancellation" do
      grant_permission(@actor, "store.orders.cancel")
      first_order = create_order
      second_order = create_order
      request_id = SecureRandom.uuid
      authorization = authorize!(
        order_ids: [ first_order.public_id, second_order.public_id ],
        action: "cancel_pending",
        request_id: request_id
      )
      second_order.update!(status: "paid")

      result = Commerce::HighRiskOrderAction.call(
        **execute_attributes(
          order_ids: [ first_order.public_id, second_order.public_id ],
          action: "cancel_pending",
          request_id: request_id,
          authorization: authorization
        )
      )

      assert_predicate result, :failure?
      assert_equal I18n.t("mcweb.services.errors.order_cannot_cancel"), result.error
      assert first_order.reload.pending?
      assert second_order.reload.paid?
      assert_not Commerce::HighRiskOperation.exists?(request_id: request_id)
    end

    test "same eligible target changed after preview invalidates challenge" do
      grant_permission(@actor, "store.orders.cancel")
      order = create_order
      request_id = SecureRandom.uuid
      authorization = authorize!(
        order_ids: [ order.public_id ],
        action: "cancel_pending",
        request_id: request_id
      )
      order.update!(notes: "Target changed after review")

      result = Commerce::HighRiskOrderAction.call(
        **execute_attributes(
          order_ids: [ order.public_id ],
          action: "cancel_pending",
          request_id: request_id,
          authorization: authorization
        )
      )

      assert_predicate result, :failure?
      assert_equal I18n.t("mcweb.services.errors.high_risk_authorization_invalid"), result.error
      assert order.reload.pending?
    end

    test "expired challenge cannot change order" do
      grant_permission(@actor, "store.orders.cancel")
      order = create_order
      request_id = SecureRandom.uuid
      authorization = authorize!(
        order_ids: [ order.public_id ],
        action: "cancel_pending",
        request_id: request_id
      )

      travel Commerce::HighRiskActionAuthorization::EXPIRES_IN + 1.second do
        result = Commerce::HighRiskOrderAction.call(
          **execute_attributes(
            order_ids: [ order.public_id ],
            action: "cancel_pending",
            request_id: request_id,
            authorization: authorization
          )
        )
        assert_predicate result, :failure?
        assert_equal I18n.t("mcweb.services.errors.high_risk_authorization_invalid"),
          result.error
      end
      assert order.reload.pending?
      assert_not Commerce::HighRiskOperation.exists?(request_id: request_id)
    end

    test "mark paid and mark fulfilled have independent successful ledgers" do
      grant_permission(@actor, "store.orders.mark_paid")
      payable = create_order
      paid_request_id = SecureRandom.uuid
      paid_authorization = authorize!(
        order_ids: [ payable.public_id ],
        action: "mark_paid",
        request_id: paid_request_id
      )
      paid = Commerce::HighRiskOrderAction.call(
        **execute_attributes(
          order_ids: [ payable.public_id ],
          action: "mark_paid",
          request_id: paid_request_id,
          authorization: paid_authorization
        )
      )
      assert_predicate paid, :success?, paid.error
      assert payable.reload.paid?
      assert payable.payment_records.where(status: "succeeded", provider: "fake").exists?

      grant_permission(@actor, "store.orders.mark_fulfilled")
      fulfilled_request_id = SecureRandom.uuid
      fulfilled_authorization = authorize!(
        order_ids: [ payable.public_id ],
        action: "mark_fulfilled",
        request_id: fulfilled_request_id
      )
      fulfilled = Commerce::HighRiskOrderAction.call(
        **execute_attributes(
          order_ids: [ payable.public_id ],
          action: "mark_fulfilled",
          request_id: fulfilled_request_id,
          authorization: fulfilled_authorization
        )
      )
      assert_predicate fulfilled, :success?, fulfilled.error
      assert payable.reload.fulfilled?
      assert_equal %w[order.mark_fulfilled order.mark_paid],
        Commerce::HighRiskOperation
          .where(request_id: [ paid_request_id, fulfilled_request_id ])
          .order(:action)
          .pluck(:action)
    end

    test "a later bulk failure rolls back earlier order and balance changes" do
      grant_permission(@actor, "store.orders.mark_paid")
      @buyer.update!(store_credit_cents: 100)
      first_order = create_order
      first_order.update!(store_credit_amount_cents: 50)
      second_order = create_order
      second_order.update!(store_credit_amount_cents: 100)
      request_id = SecureRandom.uuid
      authorization = authorize!(
        order_ids: [ first_order.public_id, second_order.public_id ],
        action: "mark_paid",
        request_id: request_id
      )

      result = Commerce::HighRiskOrderAction.call(
        **execute_attributes(
          order_ids: [ first_order.public_id, second_order.public_id ],
          action: "mark_paid",
          request_id: request_id,
          authorization: authorization
        )
      )

      assert_predicate result, :failure?
      assert_equal I18n.t("mcweb.services.errors.store_credit_insufficient"), result.error
      assert first_order.reload.pending?
      assert second_order.reload.pending?
      assert_equal 100, @buyer.reload.store_credit_cents
      assert_empty first_order.payment_records
      assert_empty second_order.payment_records
      assert_not Commerce::HighRiskOperation.exists?(request_id: request_id)
      assert_not AuditLog.where("metadata ->> 'request_id' = ?", request_id).exists?
    end

    private

    def create_order(status: "pending")
      Commerce::Order.create!(
        public_id: "ord_risk_#{SecureRandom.hex(8)}",
        order_number: "RISK#{SecureRandom.hex(5).upcase}",
        user: @buyer,
        status: status,
        subtotal_cents: 1_000,
        total_cents: 1_000,
        currency: "CNY"
      )
    end

    def authorize(order_ids:, action:, request_id: SecureRandom.uuid)
      Commerce::HighRiskOrderAction.authorize(
        actor: @actor,
        order_public_ids: order_ids,
        action: action,
        request_id: request_id,
        reason: @reason
      )
    end

    def authorize!(**attributes)
      result = authorize(**attributes)
      assert_predicate result, :success?, result.error
      result.value
    end

    def execute_attributes(order_ids:, action:, request_id:, authorization:)
      {
        actor: @actor,
        order_public_ids: order_ids,
        action: action,
        request_id: request_id,
        reason: @reason,
        authorization_token: authorization[:authorization_token],
        confirmation: authorization[:confirmation]
      }
    end
  end

  class HighRiskOrderActionConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    setup do
      @actor = create_user(account_type: "staff")
      @buyer = create_user
      grant_permission(@actor, "store.orders.cancel")
      @order = Commerce::Order.create!(
        public_id: "ord_risk_concurrent_#{SecureRandom.hex(6)}",
        order_number: "RISKC#{SecureRandom.hex(5).upcase}",
        user: @buyer,
        status: "pending",
        subtotal_cents: 1_000,
        total_cents: 1_000,
        currency: "CNY"
      )
      @request_id = SecureRandom.uuid
      @reason = "Concurrent request verification"
      authorization = Commerce::HighRiskOrderAction.authorize(
        actor: @actor,
        order_public_ids: [ @order.public_id ],
        action: "cancel_pending",
        request_id: @request_id,
        reason: @reason
      )
      assert_predicate authorization, :success?, authorization.error
      @authorization = authorization.value
    end

    teardown do
      AuditLog.where("metadata ->> 'request_id' = ?", @request_id).delete_all
      Commerce::HighRiskOperation.where(request_id: @request_id).delete_all
      Commerce::OrderEvent.where(store_order_id: @order.id).delete_all
      Commerce::Order.where(id: @order.id).delete_all
      Notification.where(user_id: [ @actor.id, @buyer.id ]).delete_all
      UserRole.where(user_id: [ @actor.id, @buyer.id ]).delete_all
      User.where(id: [ @actor.id, @buyer.id ]).delete_all
    end

    test "concurrent identical submissions commit one asset effect and return one replay" do
      ready = Queue.new
      gate = Queue.new
      results = Queue.new

      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            gate.pop
            results << Commerce::HighRiskOrderAction.call(
              actor: User.find(@actor.id),
              order_public_ids: [ @order.public_id ],
              action: "cancel_pending",
              request_id: @request_id,
              reason: @reason,
              authorization_token: @authorization[:authorization_token],
              confirmation: @authorization[:confirmation]
            )
          end
        end
      end

      2.times { ready.pop }
      2.times { gate << true }
      responses = 2.times.map { results.pop }
      threads.each(&:join)

      assert responses.all?(&:success?), responses.map(&:error).inspect
      assert_equal 1, responses.count { |result| result.value[:idempotent] }
      assert_equal 1, responses.count { |result| !result.value[:idempotent] }
      assert @order.reload.cancelled?
      assert_equal 1, Commerce::HighRiskOperation.where(request_id: @request_id).count
      assert_equal 1,
        AuditLog.by_action("commerce.order_cancel")
          .where("metadata ->> 'request_id' = ?", @request_id)
          .count
    end
  end
end
