# frozen_string_literal: true

require "test_helper"

class Payments::RecordProviderModeTest < ActiveSupport::TestCase
  setup do
    @order = Commerce::Order.create!(
      public_id: "ord_provider_mode_#{SecureRandom.hex(6)}",
      order_number: "MODE-#{SecureRandom.hex(6).upcase}",
      user: create_user,
      status: "awaiting_payment",
      subtotal_cents: 1_000,
      discount_cents: 0,
      total_cents: 1_000,
      currency: "CNY"
    )
  end

  test "infers only a consistent Stripe environment from legacy metadata" do
    test_record = create_record(
      "stripe_livemode" => false,
      "stripe_checkout_livemode" => "false"
    )
    live_record = create_record("stripe_livemode" => true)
    conflicting_record = create_record(
      "stripe_livemode" => true,
      "stripe_checkout_livemode" => false
    )

    assert_equal "test", test_record.provider_mode
    assert_equal "live", live_record.provider_mode
    assert_nil conflicting_record.provider_mode
  end

  private

  def create_record(metadata)
    Payments::Record.create!(
      order: @order,
      provider: "stripe",
      status: "failed",
      amount_cents: 1_000,
      currency: "CNY",
      metadata: metadata
    )
  end
end
