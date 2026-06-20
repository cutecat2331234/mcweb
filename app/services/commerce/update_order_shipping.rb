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
      unless Commerce::StoreFeatures.enabled?(:order_shipping_management)
        return ServiceResult.failure(error: "shipping_management_disabled")
      end

      return ServiceResult.failure(error: "Order has no shippable items.") unless order_requires_tracking?

      was_shipped = @order.shipped_at.present?
      previous_status = @order.status
      attrs = {}
      attrs[:tracking_number] = @tracking_number if @tracking_number
      attrs[:shipping_carrier] = @shipping_carrier if @shipping_carrier
      attrs[:shipped_at] = Time.current if @mark_shipped

      @order.update!(attrs) if attrs.any?

      if @mark_shipped && !was_shipped
        ensure_physical_fulfillments_fulfilled!
        @order.mark_fulfilled! if @order.may_mark_fulfilled?
        Commerce::SyncOrderFulfillmentStatus.call(order: @order.reload)
        @order.reload

        Commerce::OrderEvent.create!(
          order: @order,
          event_type: "shipped",
          from_status: previous_status,
          to_status: @order.status,
          actor: @actor,
          metadata: { tracking_number: @order.tracking_number, shipping_carrier: @order.shipping_carrier }
        )
        Commerce::DispatchOrderWebhook.call(
          order: @order,
          event_type: "order.shipped",
          to_status: @order.status,
          extra: {
            tracking_number: @order.tracking_number,
            shipping_carrier: @order.shipping_carrier,
            shipped_at: @order.shipped_at&.iso8601
          }
        )
        MailDeliveryJob.perform_later("Commerce::OrderMailer", "order_shipped", "deliver_now", args: [ @order.id ])
        Commerce::InAppNotification.order_event(
          user: @order.user,
          notification_type: "commerce.order_shipped",
          key: "order_shipped",
          order: @order,
          path: "/app/store/orders/#{@order.public_id}",
          body: tracking_summary
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

    def ensure_physical_fulfillments_fulfilled!
      @order.items.find_each do |item|
        snapshot = item.fulfillment_snapshot || {}
        next unless (snapshot["product_type"] || snapshot[:product_type]).to_s == "physical"

        fulfillment = Commerce::Fulfillment.find_by(order_item: item)
        unless fulfillment
          result = Commerce::CreateFulfillment.call(order_item: item)
          next if result.failure?

          fulfillment = result.value
        end

        fulfillment.mark_fulfilled! unless fulfillment.fulfilled?
      end
    end

    def tracking_summary
      parts = [ Commerce::InAppNotification.t("order_shipped.body", number: @order.order_number) ]
      if @order.tracking_number.present?
        parts << Commerce::InAppNotification.t(
          "order_shipped.tracking",
          carrier: @order.shipping_carrier,
          tracking_number: @order.tracking_number
        )
      end
      parts.join(" ")
    end
  end
end
