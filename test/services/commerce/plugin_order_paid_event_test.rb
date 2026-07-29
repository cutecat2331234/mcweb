# frozen_string_literal: true

require "test_helper"

class Commerce::PluginOrderPaidEventTest < ActiveSupport::TestCase
  setup do
    @order = Commerce::Order.create!(
      public_id: "order_plugin_event_#{SecureRandom.hex(6)}",
      order_number: "PLUGIN-#{SecureRandom.hex(4).upcase}",
      user: create_user,
      status: "processing",
      currency: "CNY",
      subtotal_cents: 1_000,
      total_cents: 1_000
    )
    @order.events.create!(
      event_type: Commerce::PostPaymentSideEffectsJob::COMPLETED_EVENT,
      metadata: {}
    )
  end

  test "publishes one minimal paid-order event only after the transaction commit hook" do
    callbacks = []
    events = []
    subscriber = Mcweb::Events.subscribe("commerce.order.paid") { |payload| events << payload }
    success = ServiceResult.success

    Commerce::DebitGiftCard.stub(:call, success) do
      Commerce::DebitStoreCredit.stub(:call, success) do
        Commerce::IssueFinanceInvoice.stub(:call, success) do
          ActiveRecord.stub(:after_all_transactions_commit, ->(&block) { callbacks << block }) do
            first = Commerce::CompleteOrderPayment.call(order: @order)
            replay = Commerce::CompleteOrderPayment.call(order: @order.reload)

            assert_predicate first, :success?
            assert_predicate replay, :success?
            assert_empty events
            assert_equal 1, callbacks.length
          end
        end
      end
    end

    callbacks.each(&:call)

    payload = events.sole
    assert_equal(
      {
        public_id: @order.public_id,
        status: "processing",
        total_cents: 1_000,
        currency: "CNY"
      },
      payload.fetch(:order)
    )
    assert_equal(
      1,
      @order.events.where(
        event_type: Commerce::CompleteOrderPayment::PLUGIN_ORDER_PAID_PUBLISHED_EVENT
      ).count
    )
  ensure
    Mcweb::Events.unsubscribe(subscriber) if subscriber
  end

  test "publishes the paid-order event in the stable core catalog" do
    assert_includes Mcweb::Events::CATALOG, "commerce.order.paid"
  end
end
