# frozen_string_literal: true

require "test_helper"

module Commerce
  class InventoryAdjustmentTest < ActiveSupport::TestCase
    setup do
      @actor = create_user
      grant_permission(@actor, "store.inventory.adjust")
      @product = Commerce::Product.create!(
        name: "Adjusted inventory",
        slug: "adjusted-inventory-#{SecureRandom.hex(4)}",
        product_type: "digital",
        status: "active",
        price_cents: 1_000,
        currency: "CNY",
        stock: 10
      )
      @request_id = SecureRandom.uuid
      @reason = "Reconciled against the signed warehouse count."
    end

    test "signed preview binds target state and adjustment executes once with audit" do
      authorization = authorize(delta: 3)
      assert authorization.success?

      first = execute(delta: 3, authorization: authorization.value)
      replay = execute(delta: 3, authorization: authorization.value)

      assert first.success?
      refute first.value.fetch(:idempotent)
      assert replay.success?
      assert replay.value.fetch(:idempotent)
      assert_equal 13, @product.reload.stock
      movement = Commerce::InventoryMovement.find_by!(request_id: @request_id)
      assert_equal 3, movement.available_delta
      assert_equal @reason, movement.reason
      assert AuditLog.exists?(
        action: "commerce.inventory_adjusted",
        resource_type: "Commerce::Product",
        resource_id: @product.id,
        request_id: @request_id
      )
    end

    test "state change invalidates an issued preview" do
      authorization = authorize(delta: -2)
      @product.update!(stock: 9)

      result = execute(delta: -2, authorization: authorization.value)

      assert result.failure?
      assert_equal I18n.t("mcweb.services.errors.high_risk_authorization_invalid"), result.error
      assert_equal 9, @product.reload.stock
      refute Commerce::InventoryMovement.exists?(request_id: @request_id)
    end

    test "audit failure rolls back stock and movement" do
      authorization = authorize(delta: 2)

      assert_raises ActiveRecord::StatementInvalid do
        Administration::AuditLogger.stub(
          :call,
          ->(**) { raise ActiveRecord::StatementInvalid, "audit unavailable" }
        ) do
          execute(delta: 2, authorization: authorization.value)
        end
      end

      assert_equal 10, @product.reload.stock
      refute Commerce::InventoryMovement.exists?(request_id: @request_id)
    end

    test "permission and zero-delta checks fail before issuing a token" do
      denied = Commerce::InventoryAdjustment.call(
        actor: create_user,
        target: @product,
        delta: 2,
        request_id: SecureRandom.uuid,
        reason: @reason,
        authorize_only: true
      )
      invalid = Commerce::InventoryAdjustment.call(
        actor: @actor,
        target: @product,
        delta: 0,
        request_id: SecureRandom.uuid,
        reason: @reason,
        authorize_only: true
      )

      assert denied.failure?
      assert_equal I18n.t("mcweb.services.errors.high_risk_unauthorized"), denied.error
      assert invalid.failure?
      assert_equal I18n.t("mcweb.services.errors.inventory_delta_invalid"), invalid.error
    end

    private

    def authorize(delta:)
      Commerce::InventoryAdjustment.call(
        actor: @actor,
        target: @product,
        delta:,
        request_id: @request_id,
        reason: @reason,
        authorize_only: true
      )
    end

    def execute(delta:, authorization:)
      Commerce::InventoryAdjustment.call(
        actor: @actor,
        target: @product,
        delta:,
        request_id: @request_id,
        reason: @reason,
        authorization_token: authorization.fetch(:authorization_token),
        confirmation: authorization.fetch(:confirmation)
      )
    end
  end
end
