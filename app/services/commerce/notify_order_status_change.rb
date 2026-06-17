# frozen_string_literal: true

module Commerce
  class NotifyOrderStatusChange < ApplicationService
    STATUS_CONFIG = {
      "processing" => { mailer: :order_processing, preference: "commerce.order_processing" },
      "fulfilling" => { mailer: :order_fulfilling, preference: "commerce.order_fulfilling" },
      "fulfilled" => { mailer: :order_fulfilled, preference: "commerce.order_fulfilled" },
      "completed" => { mailer: :order_completed, preference: "commerce.order_completed" },
      "cancelled" => { mailer: :order_cancelled, preference: "commerce.order_cancelled" },
      "refunded" => { mailer: :order_cancelled, preference: "commerce.order_cancelled" }
    }.freeze

    WEBHOOK_EVENTS = {
      "cancelled" => "order.cancelled",
      "fulfilled" => "order.fulfilled"
    }.freeze

    def initialize(order:, from_status: nil)
      @order = order
      @from_status = from_status
    end

    def call
      return ServiceResult.success(skipped: true) if @from_status == @order.status

      dispatch_webhook!

      config = STATUS_CONFIG[@order.status]
      return ServiceResult.success unless config

      user = @order.user
      label = Commerce::GenerateOrderReceiptPdf::STATUS_LABELS[@order.status] || @order.status
      Commerce::NotifyOrderEvent.call(
        user: user,
        notification_type: config[:preference],
        title: "订单状态更新",
        body: "订单 #{@order.order_number} 现为：#{label}",
        path: "#{Mcweb::Paths::APP_PREFIX}/store/orders/#{@order.public_id}"
      )

      if NotificationPreference.enabled?(user, channel: "email", notification_type: config[:preference])
        MailDeliveryJob.perform_later("Commerce::OrderMailer", config[:mailer].to_s, "deliver_now", args: [ @order.id ])
      end

      ServiceResult.success
    end

  private

    def dispatch_webhook!
      event_type = WEBHOOK_EVENTS[@order.status] || "order.status_changed"
      Commerce::DispatchOrderWebhook.call(
        order: @order,
        event_type: event_type,
        from_status: @from_status,
        to_status: @order.status
      )
    end
  end
end
