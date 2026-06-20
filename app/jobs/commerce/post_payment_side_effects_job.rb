# frozen_string_literal: true

module Commerce
  class PostPaymentSideEffectsJob < ApplicationJob
    queue_as :default

    COMPLETED_EVENT = "post_payment_side_effects_completed"
    NOTIFIED_EVENT = "payment_confirmation_notified"

    def perform(order_id)
      Commerce::Order.transaction do
        order = Commerce::Order.lock.find_by(id: order_id)
        return unless order
        return if order.events.exists?(event_type: COMPLETED_EVENT)
        return unless order.status.in?(%w[paid processing fulfilling fulfilled completed])

        unless order.events.exists?(event_type: NOTIFIED_EVENT)
          enqueue_payment_notifications!(order)
          order.events.create!(event_type: NOTIFIED_EVENT, metadata: {})
        end

        run_non_notification_side_effects!(order)

        order.events.create!(
          event_type: COMPLETED_EVENT,
          metadata: {}
        )
      end
    end

    private

    def enqueue_payment_notifications!(order)
      MailDeliveryJob.perform_later("Commerce::OrderMailer", "payment_confirmed", "deliver_now", args: [ order.id ])
      Commerce::InAppNotification.order_event(
        user: order.user,
        notification_type: "commerce.payment_confirmed",
        key: "payment_confirmed",
        order: order
      )
    end

    def run_non_notification_side_effects!(order)
      Community::CheckAutoBadges.call(user: order.user)
      order.items.includes(:product).find_each do |item|
        next unless item.product

        Commerce::SubscribeProductDiscussion.call(user: order.user, product: item.product)
      end
    end
  end
end
