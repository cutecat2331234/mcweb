# frozen_string_literal: true

require "test_helper"

module Commerce
  class InventoryLedgerTest < ActiveSupport::TestCase
    setup do
      @user = create_user
      @product = Commerce::Product.create!(
        name: "Ledger product",
        slug: "ledger-product-#{SecureRandom.hex(4)}",
        product_type: "digital",
        status: "active",
        price_cents: 1_000,
        currency: "CNY",
        stock: 5
      )
    end

    test "creating an order reserves inventory and writes an immutable movement" do
      result = Commerce::CreateOrder.call(cart: cart_with(quantity: 2), user: @user)

      assert result.success?
      order = result.value
      reservation = Commerce::InventoryReservation.find_by!(order:)
      assert_predicate reservation, :active?
      assert_equal 2, reservation.quantity
      assert reservation.expires_at.present?
      assert_equal 3, @product.reload.stock

      movement = Commerce::InventoryMovement.find_by!(reservation:, movement_type: "reserve")
      assert_equal(-2, movement.available_delta)
      assert_equal 2, movement.reserved_delta
      assert_equal 3, movement.available_after
      assert_equal 2, movement.reserved_after
      assert_raises(ActiveRecord::ReadOnlyRecord) { movement.update!(reason: "tamper") }
    end

    test "payment confirmation converts reserved units to sold exactly once" do
      order = Commerce::CreateOrder.call(cart: cart_with(quantity: 2), user: @user).value
      order.submit_payment!
      order.mark_paid!

      first = Commerce::ConfirmInventoryReservations.call(order:)
      replay = Commerce::ConfirmInventoryReservations.call(order:)

      assert first.success?
      assert replay.success?
      reservation = order.inventory_reservations.first.reload
      assert_predicate reservation, :confirmed?
      assert_equal 1, Commerce::InventoryMovement.where(reservation:, movement_type: "confirm").count
      movement = Commerce::InventoryMovement.find_by!(reservation:, movement_type: "confirm")
      assert_equal 0, movement.reserved_after
      assert_equal 2, movement.sold_after
      assert_equal 3, @product.reload.stock
    end

    test "cancellation releases active reservations without duplicate stock" do
      order = Commerce::CreateOrder.call(cart: cart_with(quantity: 2), user: @user).value

      first = Commerce::CancelOrder.call(order:, reason: "buyer_cancelled")
      second = Commerce::CancelOrder.call(order:, reason: "buyer_cancelled")

      assert first.success?
      assert second.failure?
      assert_equal 5, @product.reload.stock
      reservation = order.inventory_reservations.first.reload
      assert_predicate reservation, :released?
      assert_equal 1, Commerce::InventoryMovement.where(reservation:, movement_type: "release").count
      assert_equal 0, Commerce::InventoryMovement.find_by!(reservation:, movement_type: "release").reserved_after
    end

    test "expired reservation cancels order and records expiry release" do
      order = Commerce::CreateOrder.call(cart: cart_with(quantity: 1), user: @user).value
      reservation = order.inventory_reservations.first
      reservation.update!(expires_at: 1.minute.ago)

      Commerce::ExpireInventoryReservationsJob.perform_now

      assert_predicate order.reload, :cancelled?
      assert_predicate reservation.reload, :expired?
      assert_equal 5, @product.reload.stock
      assert Commerce::InventoryMovement.exists?(reservation:, movement_type: "expire")
    end

    private

    def cart_with(quantity:)
      Commerce::Cart.create!(user: @user).tap do |cart|
        cart.items.create!(product: @product, quantity:)
      end
    end
  end
end
