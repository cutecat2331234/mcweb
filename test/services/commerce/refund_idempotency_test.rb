# frozen_string_literal: true

require "test_helper"

class Commerce::RefundIdempotencyTest < ActiveSupport::TestCase
  class CountingProvider
    attr_reader :calls, :statuses

    def initialize
      @calls = 0
      @statuses = []
    end

    def process_refund(refund)
      @calls += 1
      @statuses << refund.reload.status
      ServiceResult.success(refund)
    end
  end

  setup do
    @user = create_user
    @admin = create_user
    @order = Commerce::Order.create!(
      public_id: "ord_refund_idem_#{SecureRandom.hex(6)}",
      order_number: "RID#{SecureRandom.hex(4).upcase}",
      user: @user,
      status: "paid",
      subtotal_cents: 1_000,
      total_cents: 1_000,
      currency: "CNY"
    )
    @payment = Payments::Record.create!(
      order: @order,
      provider: "fake",
      status: "succeeded",
      amount_cents: 1_000,
      currency: "CNY",
      provider_payment_id: "refund_idem_#{SecureRandom.hex(6)}"
    )
    @refund = Commerce::Refund.create!(
      order: @order,
      payment_record: @payment,
      status: "pending",
      amount_cents: 1_000,
      requested_by: @user
    )
  end

  test "claims the refund before calling the provider and never calls it again for a completed replay" do
    provider = CountingProvider.new

    with_provider(provider) do
      first = process_refund
      replay = process_refund

      assert first.success?, first.error
      assert replay.success?, replay.error
    end

    assert_equal 1, provider.calls
    assert_equal [ "approved" ], provider.statuses
    processed_events = @order.events
      .where(event_type: "refund_processed")
      .where("metadata ->> 'refund_id' = ?", @refund.id.to_s)
    assert_equal 1, processed_events.count
    assert @refund.reload.completed?
  end

  test "does not call the provider while another worker owns an approved refund" do
    @refund.update!(status: "approved", approved_by: @admin)
    provider = CountingProvider.new

    result = with_provider(provider) { process_refund }

    assert result.failure?
    assert_equal 0, provider.calls
    assert @refund.reload.approved?

    enable_refund_window!
    anchor_order_payment_at!(@order)
    request = Commerce::RequestRefund.call(order: @order, user: @user, amount_cents: 100)
    assert request.failure?
    assert_equal 1, @order.refunds.count
  end

  test "restores gift card and wallet balances from cumulative completed refunds" do
    @refund.destroy!
    card = Commerce::GiftCard.create!(
      code: "GC#{SecureRandom.hex(6).upcase}",
      balance_cents: 0,
      initial_balance_cents: 1_000,
      currency: "CNY",
      active: true
    )
    @order.update!(
      subtotal_cents: 3_000,
      gift_card: card,
      gift_card_amount_cents: 1_000,
      store_credit_amount_cents: 1_000
    )
    @user.update!(store_credit_cents: 0)
    provider = CountingProvider.new

    with_provider(provider) do
      2.times do
        result = Commerce::ProcessRefund.call(
          order: @order,
          payment_record: @payment,
          amount_cents: 250,
          approved_by: @admin
        )
        assert result.success?, result.error
      end
    end

    assert_equal 500, card.reload.balance_cents
    assert_equal 500, @order.reload.gift_card_restored_cents
    assert_equal 500, @user.reload.store_credit_cents
    assert_equal 500, @order.store_credit_restored_cents
    assert_equal 2, provider.calls
  end

  test "does not treat a separate pending reservation as money already refunded" do
    @refund.update!(amount_cents: 300)
    approved_refund = Commerce::Refund.create!(
      order: @order,
      payment_record: @payment,
      status: "pending",
      amount_cents: 700,
      requested_by: @user
    )
    provider = CountingProvider.new

    result = with_provider(provider) do
      Commerce::ProcessRefund.call(
        order: @order,
        payment_record: @payment,
        amount_cents: 700,
        approved_by: @admin,
        existing_refund: approved_refund
      )
    end

    assert result.success?, result.error
    assert_equal "paid", @order.reload.status
    assert @refund.reload.pending?
    assert approved_refund.reload.completed?
    assert_equal 1, provider.calls
  end

  private

  def with_provider(provider)
    original = Payments::Provider.method(:for)
    Payments::Provider.define_singleton_method(:for) { |_provider_name| provider }
    yield
  ensure
    Payments::Provider.define_singleton_method(:for, original)
  end

  def process_refund
    Commerce::ProcessRefund.call(
      order: @order,
      payment_record: @payment,
      amount_cents: @refund.amount_cents,
      approved_by: @admin,
      existing_refund: @refund
    )
  end
end
