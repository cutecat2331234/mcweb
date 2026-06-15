# frozen_string_literal: true

module Commerce
  class UpdateOrderShipping < ApplicationService
    def initialize(order:, actor:, tracking_number: nil, shipping_carrier: nil, mark_shipped: false)
      @order = order
      @actor = actor
      @tracking_number = tracking_number.to_s.strip.presence
      @shipping_carrier = shipping_carrier.to_s.strip.presence
      @mark_shipped = ActiveModel::Type::Boolean.new.cast(mark_shipped)
    end

    def call
      return ServiceResult.failure(error: "Order has no shippable items.") unless order_requires_tracking?

      was_shipped = @order.shipped_at.present?
      attrs = {}
      attrs[:tracking_number] = @tracking_number if @tracking_number
      attrs[:shipping_carrier] = @shipping_carrier if @shipping_carrier
      if @mark_shipped
        attrs[:shipped_at] = Time.current
        attrs[:status] = "fulfilled" if %w[paid processing fulfilling].include?(@order.status)
      end

      @order.update!(attrs) if attrs.any?

      if @mark_shipped && !was_shipped
        Commerce::OrderEvent.create!(
          order: @order,
          event_type: "shipped",
          from_status: @order.status,
          to_status: @order.status,
          actor: @actor,
          metadata: { tracking_number: @order.tracking_number, shipping_carrier: @order.shipping_carrier }
        )
        MailDeliveryJob.perform_later("Commerce::OrderMailer", "order_shipped", "deliver_now", args: [ @order.id ])
        Commerce::NotifyOrderEvent.call(
          user: @order.user,
          notification_type: "commerce.order_shipped",
          title: "订单已发货",
          body: tracking_summary,
          path: "/store/orders/#{@order.public_id}"
        )
      end

      ServiceResult.success(@order)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def order_requires_tracking?
      @order.items.any? do |item|
        snapshot = item.fulfillment_snapshot || {}
        type = snapshot["product_type"] || snapshot[:product_type]
        type.to_s == "physical"
      end
    end

    def tracking_summary
      parts = [ "订单 #{@order.order_number} 已发货。" ]
      parts << "#{@order.shipping_carrier}：#{@order.tracking_number}" if @order.tracking_number.present?
      parts.join(" ")
    end
  end
end
