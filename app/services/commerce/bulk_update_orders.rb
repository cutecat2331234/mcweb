# frozen_string_literal: true

module Commerce
  class BulkUpdateOrders < ApplicationService
    ALLOWED_ACTIONS = %w[cancel_pending mark_fulfilled mark_paid].freeze

    def initialize(actor:, order_public_ids:, action:)
      @actor = actor
      @order_public_ids = Array(order_public_ids).map(&:to_s).uniq
      @action = action.to_s
    end

    def call
      return ServiceResult.failure(error: "未选择订单") if @order_public_ids.empty?
      return ServiceResult.failure(error: "不支持的操作") unless ALLOWED_ACTIONS.include?(@action)

      processed = 0
      failures = []

      Commerce::Order.where(public_id: @order_public_ids).find_each do |order|
        result = process_order(order)
        if result.success?
          processed += 1
        else
          failures << { id: order.public_id, error: result.error }
        end
      end

      ServiceResult.success(processed: processed, failed: failures.size, failures: failures)
    end

    private

    def process_order(order)
      case @action
      when "cancel_pending"
        return ServiceResult.failure(error: "订单不可取消") unless order.pending? || order.awaiting_payment?

        Commerce::CancelOrder.call(order: order, actor: @actor, reason: "staff_bulk")
      when "mark_fulfilled"
        return ServiceResult.failure(error: "订单不可标记发货完成") unless order.may_mark_fulfilled?

        previous_status = order.status
        order.mark_fulfilled!
        Commerce::NotifyOrderStatusChange.call(order: order, from_status: previous_status)
        ServiceResult.success
      when "mark_paid"
        return ServiceResult.failure(error: "订单不可标记已支付") unless order.pending? || order.awaiting_payment?

        order.submit_payment! if order.pending? && order.may_submit_payment?
        return ServiceResult.failure(error: "订单不可标记已支付") unless order.awaiting_payment? && order.may_mark_paid?

        order.mark_paid!
        Commerce::FulfillOrderJob.perform_later(order.id)
        ServiceResult.success
      else
        ServiceResult.failure(error: "不支持的操作")
      end
    end
  end
end
