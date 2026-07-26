# frozen_string_literal: true

require "test_helper"

class Commerce::RefundIntegrityTest < ActiveSupport::TestCase
  class CountingProvider
    attr_reader :calls

    def initialize
      @calls = 0
    end

    def process_refund(refund)
      @calls += 1
      ServiceResult.success(
        provider_refund_id: "provider_refund_#{refund.id}",
        provider_status: "succeeded",
        provider_metadata: { "confirmed" => true }
      )
    end
  end

  class BlockingProvider
    attr_reader :entered, :release, :calls

    def initialize
      @entered = Queue.new
      @release = Queue.new
      @mutex = Mutex.new
      @calls = 0
    end

    def process_refund(refund)
      first_call = @mutex.synchronize do
        @calls += 1
        @calls == 1
      end
      if first_call
        @entered << refund.id
        @release.pop
      end
      ServiceResult.success(
        provider_refund_id: "provider_refund_#{refund.id}",
        provider_status: "succeeded"
      )
    end
  end

  setup do
    @user = create_user
    @admin = create_user
    @order = create_order(total_cents: 1_000)
  end

  test "conserves refundable amounts independently for split payment records" do
    first_payment = create_payment(amount_cents: 600)
    second_payment = create_payment(amount_cents: 400)

    first = process_refund(first_payment, 600)
    overflow = process_refund(first_payment, 1)
    second = process_refund(second_payment, 400)

    assert first.success?, first.error
    assert overflow.failure?
    assert overflow.error.present?
    assert second.success?, second.error
    assert @order.reload.refunded?
    assert_equal 600, first_payment.refunds.completed.sum(:amount_cents)
    assert_equal 400, second_payment.refunds.completed.sum(:amount_cents)
  end

  test "concurrent refunds reserve one payment balance before either provider call completes" do
    payment = create_payment(amount_cents: 1_000)
    provider = BlockingProvider.new
    ready = Queue.new
    gate = Queue.new
    results = Queue.new

    with_provider(provider) do
      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            gate.pop
            result = Commerce::ProcessRefund.call(
              order: Commerce::Order.find(@order.id),
              payment_record: Payments::Record.find(payment.id),
              amount_cents: 700,
              approved_by: User.find(@admin.id)
            )
            results << result
          end
        end
      end

      2.times { ready.pop }
      2.times { gate << true }
      provider.entered.pop
      rejected = results.pop
      provider.release << true
      accepted = results.pop
      threads.each(&:join)

      assert rejected.failure?
      assert_equal I18n.t("mcweb.services.errors.refund_exceeds_balance"), rejected.error
      assert accepted.success?, accepted.error
    end

    assert_equal 700, payment.refunds.completed.sum(:amount_cents)
    assert_equal 1, payment.refunds.count
    assert_equal 1, provider.calls
  end

  test "does not restore order value until duplicate successful payments are refunded" do
    @order.update!(store_credit_amount_cents: 1_000)
    @user.update!(store_credit_cents: 0)
    duplicate_payment = create_payment(amount_cents: 1_000)
    intended_payment = create_payment(amount_cents: 1_000)

    duplicate = process_refund(duplicate_payment, 1_000)

    assert duplicate.success?, duplicate.error
    assert_equal "paid", @order.reload.status
    assert_equal 0, @user.reload.store_credit_cents
    assert_equal 0, @order.store_credit_restored_cents

    intended = process_refund(intended_payment, 1_000)

    assert intended.success?, intended.error
    assert @order.reload.refunded?
    assert_equal 1_000, @user.reload.store_credit_cents
    assert_equal 1_000, @order.store_credit_restored_cents
  end

  test "retries a failed local restoration without calling the provider twice" do
    @order.update!(store_credit_amount_cents: 1_000)
    @user.update!(store_credit_cents: 0)
    payment = create_payment(amount_cents: 1_000)
    refund = Commerce::Refund.create!(
      order: @order,
      payment_record: payment,
      status: "pending",
      amount_cents: 1_000,
      requested_by: @user
    )
    provider = CountingProvider.new

    failed = with_provider(provider) do
      with_stock_restoration_failure do
        process_refund(payment, 1_000, existing_refund: refund)
      end
    end

    assert failed.failure?
    assert_equal "restoration_failed", failed.code
    assert_equal 1, provider.calls
    assert refund.reload.provider_confirmed?
    assert refund.restoration_failed?
    assert_equal 0, @user.reload.store_credit_cents
    assert_equal 0, @order.reload.store_credit_restored_cents

    recovered = with_provider(provider) do
      process_refund(payment, 1_000, existing_refund: refund)
    end

    assert recovered.success?, recovered.error
    assert_equal 1, provider.calls
    assert refund.reload.completed?
    assert refund.restoration_completed?
    assert_equal 1_000, @user.reload.store_credit_cents
  end

  test "full refunds revoke digital entitlements issued by the order" do
    payment = create_payment(amount_cents: 1_000)
    product = Commerce::Product.create!(
      name: "Download",
      slug: "refund-download-#{SecureRandom.hex(6)}",
      public_id: "prod_#{SecureRandom.hex(8)}",
      product_type: "digital",
      status: "active",
      price_cents: 1_000,
      currency: "CNY",
      minimum_quantity: 1
    )
    item = Commerce::OrderItem.create!(
      order: @order,
      product: product,
      product_name: product.name,
      quantity: 1,
      unit_price_cents: 1_000,
      total_cents: 1_000
    )
    entitlement = Commerce::UserEntitlement.create!(
      user: @user,
      product: product,
      source_order_item: item,
      starts_at: Time.current
    )

    result = process_refund(payment, 1_000)

    assert result.success?, result.error
    assert entitlement.reload.revoked_at.present?
    assert_not entitlement.currently_active?
  end

  private

  def create_order(total_cents:)
    Commerce::Order.create!(
      public_id: "ord_integrity_#{SecureRandom.hex(6)}",
      order_number: "RINT#{SecureRandom.hex(4).upcase}",
      user: @user,
      status: "paid",
      subtotal_cents: total_cents,
      total_cents: total_cents,
      currency: "CNY"
    )
  end

  def create_payment(amount_cents:)
    Payments::Record.create!(
      order: @order,
      provider: "fake",
      status: "succeeded",
      amount_cents: amount_cents,
      currency: "CNY",
      provider_payment_id: "refund_integrity_#{SecureRandom.hex(8)}"
    )
  end

  def process_refund(payment, amount_cents, existing_refund: nil)
    Commerce::ProcessRefund.call(
      order: @order,
      payment_record: payment,
      amount_cents: amount_cents,
      approved_by: @admin,
      existing_refund: existing_refund
    )
  end

  def with_provider(provider)
    original = Payments::Provider.method(:for)
    Payments::Provider.define_singleton_method(:for) { |_name| provider }
    yield
  ensure
    Payments::Provider.define_singleton_method(:for, original)
  end

  def with_stock_restoration_failure
    original = Commerce::RestoreStockPartial.method(:call)
    Commerce::RestoreStockPartial.define_singleton_method(:call) do |**|
      ServiceResult.failure(error: "simulated_stock_restoration_failure")
    end
    yield
  ensure
    Commerce::RestoreStockPartial.define_singleton_method(:call, original)
  end
end
