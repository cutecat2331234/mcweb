# frozen_string_literal: true

module Commerce
  class ManualFulfillmentAction < ApplicationService
    ACTIONS = %w[retry cancel].freeze
    ELIGIBLE_ORDER_STATUSES = %w[paid processing fulfilling fulfilled completed].freeze

    def initialize(
      actor:,
      fulfillment:,
      action:,
      request_id:,
      reason:,
      authorization_token: nil,
      confirmation: nil,
      authorize_only: false,
      ip_address: nil,
      user_agent: nil
    )
      @actor = actor
      @fulfillment = fulfillment
      @action = action.to_s
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
      @fulfillment.reload
      if !@authorize_only && @request_id
        existing = FulfillmentAttempt.find_by(idempotency_key: "fulfillment-action:#{@request_id}")
        return idempotency_result(existing) if existing
      end
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
        all_of: permission,
        failure_code: "high_risk_unauthorized"
      ) do |actor|
        @actor = actor
        yield
      end
    end

    def authorize
      HighRiskActionAuthorization.issue(
        actor: @actor,
        action: authorization_action,
        targets: targets,
        state: state,
        attributes: attributes,
        request_id: @request_id,
        reason: @reason
      ).then do |result|
        next result unless result.success?

        ServiceResult.success(
          result.value.merge(
            preview: preview
          )
        )
      end
    end

    def execute
      idempotency_key = "fulfillment-action:#{@request_id}"
      existing = FulfillmentAttempt.find_by(idempotency_key:)
      return idempotency_result(existing) if existing

      attempt = nil
      should_enqueue = false
      Fulfillment.transaction(requires_new: true) do
        @fulfillment.lock!
        @fulfillment.order.lock!
        @fulfillment.reload

        existing = FulfillmentAttempt.find_by(idempotency_key:)
        return idempotency_result(existing) if existing
        return ServiceResult.failure(error: "high_risk_authorization_invalid") unless authorization_valid?
        return ServiceResult.failure(error: "high_risk_confirmation_invalid") unless confirmation_valid?

        failure = action_state_failure
        return failure if failure

        before = fulfillment_state
        attempt = create_action_attempt!(idempotency_key)
        if @action == "retry"
          supersede_active_connector_tasks!
          @fulfillment.update!(
            status: "pending",
            last_error: nil,
            next_attempt_at: nil,
            cancelled_at: nil,
            cancel_reason: nil
          )
          should_enqueue = true
        else
          cancel_active_connector_tasks!
          @fulfillment.update!(
            status: "cancelled",
            next_attempt_at: nil,
            cancelled_at: Time.current,
            cancel_reason: @reason
          )
        end

        attempt.update!(
          status: "succeeded",
          completed_at: Time.current,
          result_summary: {
            "success" => true,
            "result" => @action == "retry" ? "requeued" : "cancelled"
          }
        )
        Administration::AuditLogger.call(
          actor: @actor,
          action: "commerce.fulfillment_#{@action}",
          resource: @fulfillment,
          request_id: @request_id,
          reason: @reason,
          before_state: before,
          after_state: fulfillment_state,
          metadata: {
            fulfillment_attempt_id: attempt.id,
            delivery_id: @fulfillment.delivery_id,
            confirmation_method: "signed_typed_challenge"
          },
          ip_address: @ip_address,
          user_agent: @user_agent
        )
        if @action == "cancel"
          Commerce::DomainEvents.publish_after_commit(
            "commerce.fulfillment.cancelled",
            Commerce::DomainEvents.fulfillment(@fulfillment, attempt:)
          )
        end
      end

      if should_enqueue
        ActiveRecord.after_all_transactions_commit do
          Minecraft::EnsureInstanceRunningJob.perform_later(@fulfillment.id)
        end
      end

      ServiceResult.success(
        fulfillment: @fulfillment,
        attempt: attempt,
        idempotent: false,
        action: @action
      )
    rescue ActiveRecord::RecordNotUnique
      idempotency_result(FulfillmentAttempt.find_by!(idempotency_key: "fulfillment-action:#{@request_id}"))
    rescue ActiveRecord::StaleObjectError
      ServiceResult.failure(error: "fulfillment_state_changed")
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    def validation_failure
      return ServiceResult.failure(error: "fulfillment_action_invalid") unless ACTIONS.include?(@action)
      return ServiceResult.failure(error: "high_risk_unauthorized") unless @actor&.permission?(permission)
      return ServiceResult.failure(error: "high_risk_request_id_invalid") unless @request_id
      return ServiceResult.failure(error: "high_risk_reason_required") if @reason.blank?
      return ServiceResult.failure(error: "high_risk_reason_too_long") if @reason.length > HighRiskActionAuthorization::MAX_REASON_LENGTH

      action_state_failure
    end

    def action_state_failure
      return ServiceResult.failure(error: "fulfillment_not_retryable") if @action == "retry" && !retryable_state?
      return ServiceResult.failure(error: "fulfillment_not_cancellable") if @action == "cancel" && !cancellable_state?

      nil
    end

    def retryable_state?
      @fulfillment.retryable? &&
        ELIGIBLE_ORDER_STATUSES.include?(@fulfillment.order.status) &&
        inventory_ready?
    end

    def cancellable_state?
      (@fulfillment.pending? || @fulfillment.failed? || @fulfillment.processing?) &&
        !@fulfillment.fulfilled? &&
        !@fulfillment.cancelled?
    end

    def inventory_ready?
      reservation = @fulfillment.order_item.inventory_reservation
      reservation.nil? || reservation.confirmed?
    end

    def authorization_valid?
      HighRiskActionAuthorization.valid?(
        @authorization_token,
        actor: @actor,
        action: authorization_action,
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
        action: authorization_action,
        targets: targets,
        request_id: @request_id
      )
    end

    def authorization_action
      "fulfillment.#{@action}"
    end

    def permission
      HighRiskActionAuthorization.permission_for(authorization_action)
    end

    def targets
      [ {
        type: "Commerce::Fulfillment",
        id: @fulfillment.id,
        identifier: @fulfillment.delivery_id
      } ]
    end

    def state
      fulfillment_state.merge(
        order_status: @fulfillment.order.status,
        order_updated_at: @fulfillment.order.updated_at,
        reservation_status: @fulfillment.order_item.inventory_reservation&.status,
        active_connector_tasks: @fulfillment.connector_tasks.where(status: %w[pending claimed]).count,
        completed_connector_task: @fulfillment.connector_tasks.completed.exists?
      )
    end

    def fulfillment_state
      {
        status: @fulfillment.status,
        attempts_count: @fulfillment.attempts_count,
        max_attempts: @fulfillment.max_attempts,
        lock_version: @fulfillment.lock_version,
        updated_at: @fulfillment.updated_at
      }
    end

    def attributes
      { action: @action }
    end

    def preview
      {
        delivery_id: @fulfillment.delivery_id,
        order_number: @fulfillment.order.order_number,
        product_name: @fulfillment.order_item.product_name,
        current_status: @fulfillment.status,
        next_status: @action == "retry" ? "pending" : "cancelled",
        attempts_count: @fulfillment.attempts_count,
        max_attempts: @fulfillment.max_attempts,
        inventory_status: @fulfillment.order_item.inventory_reservation&.status || "legacy",
        active_entitlement: active_entitlement?,
        active_connector_tasks: @fulfillment.connector_tasks.where(status: %w[pending claimed]).count
      }
    end

    def active_entitlement?
      UserEntitlement.currently_active.exists?(
        source_order_item_id: @fulfillment.store_order_item_id
      )
    end

    def create_action_attempt!(idempotency_key)
      attempt_number = [
        @fulfillment.attempts.maximum(:attempt_number).to_i,
        @fulfillment.attempts_count
      ].max + 1
      @fulfillment.attempts.create!(
        attempt_number: attempt_number,
        idempotency_key: idempotency_key,
        trigger: "manual",
        action: @action,
        status: "processing",
        actor: @actor,
        reason: @reason,
        request_id: @request_id,
        started_at: Time.current,
        request_data: {
          action: @action,
          request_fingerprint: request_fingerprint
        },
        response_data: {},
        result_summary: {}
      )
    end

    def request_fingerprint
      HighRiskActionAuthorization.request_fingerprint(
        actor: @actor,
        action: authorization_action,
        targets: targets,
        attributes: attributes,
        request_id: @request_id,
        reason: @reason
      )
    end

    def supersede_active_connector_tasks!
      @fulfillment.connector_tasks.where(status: %w[pending claimed]).find_each do |task|
        task.fail!(error: "superseded_by_manual_retry")
      end
    end

    def cancel_active_connector_tasks!
      @fulfillment.connector_tasks.where(status: %w[pending claimed]).find_each do |task|
        task.fail!(error: "fulfillment_cancelled")
      end
    end

    def idempotency_result(existing)
      expected = existing&.fulfillment == @fulfillment &&
        existing&.actor == @actor &&
        existing&.action == @action &&
        existing&.request_data&.fetch("request_fingerprint", nil) == request_fingerprint
      return ServiceResult.failure(error: "high_risk_idempotency_conflict") unless expected

      ServiceResult.success(
        fulfillment: @fulfillment.reload,
        attempt: existing,
        idempotent: true,
        action: @action
      )
    end
  end
end
