# frozen_string_literal: true

module Commerce
  class SyncOrderFulfillmentStatus < ApplicationService
    def initialize(order:)
      @order = order
    end

    def call
      Commerce::Order.transaction do
        @order = Commerce::Order.lock.find(@order.id)
        return ServiceResult.success(@order) if @order.completed?

        return ServiceResult.success(@order) unless all_items_fulfilled?

        was_fulfilled = @order.fulfilled?
        previous_status = @order.status

        @order.mark_fulfilled! if @order.may_mark_fulfilled?

        if !was_fulfilled && @order.fulfilled?
          MailDeliveryJob.perform_later("Commerce::OrderMailer", "order_fulfilled", "deliver_now", args: [ @order.id ])
          Commerce::InAppNotification.order_event(
            user: @order.user,
            notification_type: "commerce.order_fulfilled",
            key: "order_fulfilled",
            order: @order
          )
        end

        if @order.fulfilled? && @order.may_complete?
          @order.complete!
          notify_completed! unless previous_status == "completed"
        end

        ServiceResult.success(@order)
      end
    rescue AASM::InvalidTransition => e
      ServiceResult.failure(error: e.message)
    end

    private

    def all_items_fulfilled?
      item_ids = @order.items.pluck(:id)
      return false if item_ids.empty?

      fulfilled_item_ids = @order.fulfillments.where(status: "fulfilled").distinct.pluck(:store_order_item_id)
      (item_ids - fulfilled_item_ids).empty?
    end

    def notify_completed!
      MailDeliveryJob.perform_later("Commerce::OrderMailer", "order_completed", "deliver_now", args: [ @order.id ])
      Commerce::InAppNotification.order_event(
        user: @order.user,
        notification_type: "commerce.order_completed",
        key: "order_completed",
        order: @order
      )

      delay_days = SiteSetting.get("store.review_request_delay_days", "3").to_i
      if delay_days <= 0
        Commerce::SendReviewRequest.call(order: @order)
      else
        Commerce::SendReviewRequestJob.set(wait: delay_days.days).perform_later(@order.id)
      end
    end
  end
end
