# frozen_string_literal: true

module Commerce
  class HighRiskOrderAction < ApplicationService
    ACTION_MAP = {
      "cancel_pending" => "order.cancel",
      "mark_paid" => "order.mark_paid",
      "mark_fulfilled" => "order.mark_fulfilled"
    }.freeze

    class << self
      def authorize(**args)
        new(**args).authorize
      end
    end

    def initialize(actor:, order_public_ids:, action:, request_id:, reason:,
                   authorization_token: nil, confirmation: nil, ip_address: nil,
                   user_agent: nil)
      @actor = actor
      @order_public_ids = Array(order_public_ids).map(&:to_s).reject(&:blank?).uniq.sort
      @bulk_action = action.to_s
      @action = ACTION_MAP[@bulk_action]
      @request_id = Commerce::HighRiskActionAuthorization.normalize_request_id(request_id)
      @reason = Commerce::HighRiskActionAuthorization.normalize_reason(reason)
      @authorization_token = authorization_token.to_s
      @confirmation = confirmation.to_s.strip
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def authorize
      failure = validation_failure
      return failure if failure
      return eligibility_failure unless eligible?

      auth = Commerce::HighRiskActionAuthorization.issue(
        actor: @actor,
        action: @action,
        targets: targets,
        state: current_state,
        attributes: attributes,
        request_id: @request_id,
        reason: @reason
      )
      return auth if auth.failure?

      ServiceResult.success(
        auth.value.merge(
          preview: {
            action: @action,
            count: orders.size,
            before: current_state,
            after: predicted_state
          }
        )
      )
    end

    def call
      failure = validation_failure
      return failure if failure

      @request_fingerprint = request_fingerprint
      existing = Commerce::HighRiskOperation.find_by(request_id: @request_id)
      return idempotency_result(existing) if existing
      return ServiceResult.failure(error: "high_risk_authorization_invalid") if @authorization_token.blank?
      unless Commerce::HighRiskActionAuthorization.confirmation_valid?(
        @confirmation,
        action: @action,
        targets: targets,
        request_id: @request_id
      )
        return ServiceResult.failure(error: "high_risk_confirmation_invalid")
      end

      action_result = nil
      operation = nil
      Commerce::HighRiskOperation.transaction do
        locked_orders
        existing = Commerce::HighRiskOperation.find_by(request_id: @request_id)
        return idempotency_result(existing) if existing
        return eligibility_failure unless eligible?

        before_state = current_state
        unless Commerce::HighRiskActionAuthorization.valid?(
          @authorization_token,
          actor: @actor,
          action: @action,
          targets: targets,
          state: before_state,
          attributes: attributes,
          request_id: @request_id,
          reason: @reason
        )
          return ServiceResult.failure(error: "high_risk_authorization_invalid")
        end

        action_result = Commerce::BulkUpdateOrders.call(
          actor: @actor,
          order_public_ids: @order_public_ids,
          action: @bulk_action,
          reason: @reason,
          idempotency_key: "high-risk:#{@request_id}"
        )
        if action_result.failure? || action_result.value[:failed].to_i.positive?
          action_result = ServiceResult.failure(
            error: action_result.error.presence ||
              action_result.value[:failures]&.first&.dig(:error) ||
              "high_risk_order_action_failed"
          )
          raise ActiveRecord::Rollback
        end

        orders.each(&:reload)
        after_state = current_state
        target_user = orders.map(&:user_id).uniq.one? ? orders.first.user : nil
        resource = orders.one? ? orders.first : nil
        operation = Commerce::HighRiskOperation.create!(
          actor: @actor,
          target_user: target_user,
          action: @action,
          request_id: @request_id,
          request_fingerprint: @request_fingerprint,
          authorization_digest: Commerce::HighRiskActionAuthorization.authorization_digest(
            @authorization_token
          ),
          resource_type: resource&.class&.name,
          resource_id: resource&.id,
          resource_public_id: resource&.public_id,
          reason: @reason,
          target_snapshot: targets,
          before_state: before_state,
          after_state: after_state,
          metadata: {
            order_public_ids: @order_public_ids,
            processed: orders.size,
            confirmation_method: "signed_typed_challenge",
            request_id: @request_id
          }
        )
        orders.each do |order|
          Administration::AuditLogger.call(
            actor: @actor,
            action: "commerce.#{@action.tr('.', '_')}",
            resource: order,
            metadata: {
              high_risk_operation_id: operation.id,
              request_id: @request_id,
              order_public_id: order.public_id,
              target_user_id: order.user_id,
              confirmation_method: "signed_typed_challenge"
            },
            before_state: before_state.find { |state| state[:public_id] == order.public_id } || {},
            after_state: after_state.find { |state| state[:public_id] == order.public_id } || {},
            ip_address: @ip_address,
            user_agent: @user_agent,
            reason: @reason
          )
        end
      end
      return action_result if action_result&.failure?

      ServiceResult.success(
        processed: orders.size,
        orders: orders.map(&:reload),
        operation: operation,
        request_id: @request_id,
        idempotent: false
      )
    rescue ActiveRecord::RecordNotUnique
      existing = Commerce::HighRiskOperation.find_by(request_id: @request_id)
      return idempotency_result(existing) if existing

      ServiceResult.failure(error: "high_risk_authorization_replayed")
    rescue ActiveRecord::RecordInvalid, AASM::InvalidTransition => e
      ServiceResult.failure(error: "high_risk_order_action_failed", errors: { base: [ e.message ] })
    end

    private

    def validation_failure
      return ServiceResult.failure(error: "high_risk_action_invalid") unless @action
      return ServiceResult.failure(error: "orders_not_selected") if @order_public_ids.empty?
      return ServiceResult.failure(error: "high_risk_target_invalid") unless orders.size == @order_public_ids.size
      return ServiceResult.failure(error: "high_risk_request_id_invalid") unless @request_id
      return ServiceResult.failure(error: "high_risk_reason_required") if @reason.blank?
      if @reason.length > Commerce::HighRiskActionAuthorization::MAX_REASON_LENGTH
        return ServiceResult.failure(error: "high_risk_reason_too_long")
      end

      permission = Commerce::HighRiskActionAuthorization.permission_for(@action)
      return ServiceResult.failure(error: "high_risk_unauthorized") unless @actor&.permission?(permission)

      nil
    end

    def eligibility_failure
      error = orders.filter_map { |order| eligibility_error(order) }.first
      ServiceResult.failure(error: error || "high_risk_order_action_failed")
    end

    def eligible?
      orders.all? { |order| eligibility_error(order).nil? }
    end

    def eligibility_error(order)
      case @bulk_action
      when "cancel_pending"
        return "order_cannot_cancel" unless (order.pending? || order.awaiting_payment?) && order.may_cancel?
      when "mark_paid"
        return "order_cannot_mark_paid" unless order.pending? || order.awaiting_payment?
        return "order_payment_expired" if order.payment_expired?
      when "mark_fulfilled"
        return "order_cannot_mark_fulfilled" unless order.may_mark_fulfilled?
        return "automated_fulfillment_required" if automated_fulfillment_required?(order)
      end

      nil
    end

    def orders
      @orders ||= Commerce::Order
        .where(public_id: @order_public_ids)
        .includes(:user, items: %i[product variant])
        .order(:id)
        .to_a
    end

    def locked_orders
      @orders = Commerce::Order
        .where(public_id: @order_public_ids)
        .order(:id)
        .lock
        .to_a
      @orders.each(&:reload)
      @orders
    end

    def targets
      orders.map { |order| { type: "order", id: order.public_id, user_id: order.user_id } }
    end

    def attributes
      { bulk_action: @bulk_action, order_count: @order_public_ids.size }
    end

    def current_state
      orders.map do |order|
        {
          public_id: order.public_id,
          user_id: order.user_id,
          status: order.status,
          total_cents: order.total_cents,
          gift_card_amount_cents: order.gift_card_amount_cents,
          store_credit_amount_cents: order.store_credit_amount_cents,
          shipped_at: order.shipped_at,
          updated_at: order.updated_at
        }
      end
    end

    def predicted_state
      status = {
        "cancel_pending" => "cancelled",
        "mark_paid" => "paid",
        "mark_fulfilled" => "fulfilled"
      }.fetch(@bulk_action)
      current_state.map { |state| state.merge(status: status) }
    end

    def automated_fulfillment_required?(order)
      order.items.any? do |item|
        snapshot = item.fulfillment_snapshot || {}
        config = snapshot["fulfillment_config"] || snapshot[:fulfillment_config] || {}
        product_type = (snapshot["product_type"] || snapshot[:product_type]).to_s
        server_id = config["server_id"] || config[:server_id] ||
          config["minecraft_server_id"] || config[:minecraft_server_id]
        commands = config["commands"] || config[:commands]

        server_id.present? || Array(commands).any? || %w[membership gift_card].include?(product_type)
      end
    end

    def request_fingerprint
      Commerce::HighRiskActionAuthorization.request_fingerprint(
        actor: @actor,
        action: @action,
        targets: targets,
        attributes: attributes,
        request_id: @request_id,
        reason: @reason
      )
    end

    def idempotency_result(existing)
      return ServiceResult.failure(error: "high_risk_request_id_reused") unless existing
      unless secure_match?(existing.request_fingerprint, @request_fingerprint || request_fingerprint)
        return ServiceResult.failure(error: "high_risk_request_id_reused")
      end

      public_ids = Array(existing.metadata["order_public_ids"])
      completed_orders = Commerce::Order.where(public_id: public_ids).order(:id).to_a
      ServiceResult.success(
        processed: completed_orders.size,
        orders: completed_orders,
        operation: existing,
        request_id: existing.request_id,
        idempotent: true
      )
    end

    def secure_match?(left, right)
      left = left.to_s
      right = right.to_s
      left.bytesize == right.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(left, right)
    end
  end
end
