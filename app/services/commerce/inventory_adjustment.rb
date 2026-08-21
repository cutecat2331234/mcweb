# frozen_string_literal: true

module Commerce
  class InventoryAdjustment < ApplicationService
    MAX_ABSOLUTE_DELTA = 1_000_000

    def initialize(
      actor:,
      target:,
      delta:,
      request_id:,
      reason:,
      authorization_token: nil,
      confirmation: nil,
      authorize_only: false,
      ip_address: nil,
      user_agent: nil
    )
      @actor = actor
      @target = target
      @delta = integer_or_nil(delta)
      @request_id = HighRiskActionAuthorization.normalize_request_id(request_id)
      @reason = reason.to_s.strip
      @authorization_token = authorization_token
      @confirmation = confirmation
      @authorize_only = authorize_only
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def call
      with_fresh_authorized_actor { call_under_permission_lock }
    end

    def call_under_permission_lock
      failure = validation_failure
      return failure if failure
      return authorize if @authorize_only

      execute
    end

    private :call_under_permission_lock

    private

    def with_fresh_authorized_actor
      Identity::AuthorizedMutation.with(
        actor: @actor,
        all_of: "store.inventory.adjust",
        failure_code: "high_risk_unauthorized"
      ) do |actor|
        @actor = actor
        yield
      end
    end

    def authorize
      HighRiskActionAuthorization.issue(
        actor: @actor,
        action: "inventory.adjust",
        targets: targets,
        state: state,
        attributes: attributes,
        request_id: @request_id,
        reason: @reason
      ).then do |result|
        next result unless result.success?

        ServiceResult.success(
          result.value.merge(
            preview: {
              target: target_label,
              before: @target.stock,
              delta: @delta,
              after: @target.stock + @delta
            }
          )
        )
      end
    end

    def execute
      idempotency_key = "inventory-adjustment:#{@request_id}"
      existing = InventoryMovement.find_by(idempotency_key:)
      return idempotency_result(existing) if existing

      movement = nil
      InventoryMovement.transaction(requires_new: true) do
        @target.lock!
        @target.reload
        return ServiceResult.failure(error: "high_risk_authorization_invalid") unless authorization_valid?
        return ServiceResult.failure(error: "high_risk_confirmation_invalid") unless confirmation_valid?

        existing = InventoryMovement.find_by(idempotency_key:)
        return idempotency_result(existing) if existing

        before = @target.stock
        @target.update!(stock: before + @delta)
        movement = InventoryMovement.record!(
          target: @target,
          actor: @actor,
          movement_type: "adjustment",
          quantity: @delta.abs,
          available_delta: @delta,
          idempotency_key:,
          request_id: @request_id,
          reason: @reason,
          metadata: { before:, after: @target.stock }
        )
        Administration::AuditLogger.call(
          actor: @actor,
          action: "commerce.inventory_adjusted",
          resource: @target,
          request_id: @request_id,
          reason: @reason,
          before_state: { stock: before },
          after_state: { stock: @target.stock },
          metadata: {
            inventory_movement_public_id: movement.public_id,
            delta: @delta,
            confirmation_method: "signed_typed_challenge"
          },
          ip_address: @ip_address,
          user_agent: @user_agent
        )
        Commerce::DomainEvents.publish_after_commit(
          "commerce.inventory.adjusted",
          Commerce::DomainEvents.inventory(movement)
        )
      end

      ServiceResult.success(
        movement:,
        balance: @target.reload.stock,
        idempotent: false
      )
    rescue ActiveRecord::RecordNotUnique
      idempotency_result(InventoryMovement.find_by!(idempotency_key: "inventory-adjustment:#{@request_id}"))
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    def validation_failure
      return ServiceResult.failure(error: "high_risk_unauthorized") unless @actor&.permission?("store.inventory.adjust")
      return ServiceResult.failure(error: "inventory_target_unavailable") unless @target&.stock
      return ServiceResult.failure(error: "inventory_delta_invalid") unless @delta && @delta.nonzero?
      return ServiceResult.failure(error: "inventory_delta_invalid") if @delta.abs > MAX_ABSOLUTE_DELTA
      return ServiceResult.failure(error: "high_risk_request_id_invalid") unless @request_id
      return ServiceResult.failure(error: "high_risk_reason_required") if @reason.blank?

      nil
    end

    def authorization_valid?
      HighRiskActionAuthorization.valid?(
        @authorization_token,
        actor: @actor,
        action: "inventory.adjust",
        targets: targets,
        state: state,
        attributes: attributes,
        request_id: @request_id,
        reason: @reason
      )
    end

    def confirmation_valid?
      HighRiskActionAuthorization.confirmation_valid?(
        @confirmation,
        action: "inventory.adjust",
        targets: targets,
        request_id: @request_id
      )
    end

    def targets
      [ {
        type: @target.class.base_class.name,
        id: @target.id,
        identifier: target_label
      } ]
    end

    def state
      {
        stock: @target.stock,
        updated_at: @target.updated_at
      }
    end

    def attributes
      { delta: @delta }
    end

    def target_label
      return @target.name if @target.is_a?(Product)

      "#{@target.product.name} · #{@target.name}"
    end

    def idempotency_result(existing)
      expected_target = existing&.target == @target
      expected_delta = existing&.available_delta == @delta
      expected_actor = existing&.actor == @actor
      return ServiceResult.failure(error: "high_risk_idempotency_conflict") unless expected_target && expected_delta && expected_actor

      ServiceResult.success(
        movement: existing,
        balance: existing.available_after,
        idempotent: true
      )
    end

    def integer_or_nil(value)
      return value if value.is_a?(Integer)

      Integer(value.to_s, 10)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
