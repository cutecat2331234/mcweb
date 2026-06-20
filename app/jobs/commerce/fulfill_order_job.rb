# frozen_string_literal: true

module Commerce
  class FulfillOrderJob < ApplicationJob
    queue_as :minecraft

    def perform(order_id)
      Commerce::Order.transaction do
        order = Commerce::Order.lock.find(order_id)
        return unless %w[paid processing].include?(order.status)

        if order.paid? && order.may_start_processing?
          order.start_processing!
          notify_processing!(order)
        end
      end

      order = Commerce::Order.find(order_id)
      return unless %w[processing fulfilling].include?(order.status)

      if minecraft_maintenance_active?
        Rails.logger.info("[FulfillOrderJob] Deferred order #{order.id} — Minecraft maintenance active")
        Commerce::FulfillOrderJob.set(wait: 10.minutes).perform_later(order_id)
        return
      end

      fulfillment_failures = 0

      order.items.find_each do |order_item|
        snapshot = order_item.fulfillment_snapshot || {}
        product_type = snapshot["product_type"] || snapshot[:product_type]

        if product_type == "gift_card"
          result = Commerce::FulfillGiftCardItem.call(order_item: order_item)
          unless result.success?
            fulfillment_failures += 1
            error = result.error || result.errors&.values&.flatten&.first || "gift_card_fulfillment_failed"
            fulfillment = Commerce::Fulfillment.find_by(order_item: order_item)
            fulfillment&.mark_failed!(error: error)
            Rails.logger.warn("[FulfillOrderJob] Gift card fulfillment failed for order_item=#{order_item.id}: #{error}")
          end
          next
        end

        if product_type == "membership"
          result = Commerce::FulfillMembershipItem.call(order_item: order_item)
          unless result.success?
            fulfillment_failures += 1
            error = result.error || result.errors&.values&.flatten&.first || "membership_fulfillment_failed"
            fulfillment = Commerce::Fulfillment.find_by(order_item: order_item)
            fulfillment&.mark_failed!(error: error)
            Rails.logger.warn("[FulfillOrderJob] Membership fulfillment failed for order_item=#{order_item.id}: #{error}")
          end
          next
        end

        config = snapshot["fulfillment_config"] || snapshot[:fulfillment_config] || {}
        download_url = config["download_url"] || config[:download_url]
        server_id = config["server_id"] || config[:server_id] || config["minecraft_server_id"] || config[:minecraft_server_id]

        if download_url.present? && server_id.blank?
          result = Commerce::CreateFulfillment.call(order_item: order_item)
          unless handle_fulfillment_result!(order_item, result)
            fulfillment_failures += 1
            next
          end

          fulfillment = result.value
          fulfillment.mark_fulfilled! unless fulfillment.fulfilled?
          Commerce::SyncOrderFulfillmentStatus.call(order: order_item.order)
          Commerce::GrantProductEntitlement.call(order_item: order_item)
          next
        end

        result = Commerce::CreateFulfillment.call(order_item: order_item)
        unless handle_fulfillment_result!(order_item, result)
          fulfillment_failures += 1
          next
        end

        Minecraft::EnsureInstanceRunningJob.perform_later(result.value.id)

        entitlement_result = Commerce::GrantProductEntitlement.call(order_item: order_item)
        if entitlement_result.failure?
          Rails.logger.warn("[FulfillOrderJob] Entitlement grant failed for order_item=#{order_item.id}")
        end
      end

      order.reload
      Commerce::SyncOrderFulfillmentStatus.call(order: order)

      if fulfillment_failures.positive?
        Rails.logger.error("[FulfillOrderJob] #{fulfillment_failures} fulfillment(s) failed for order=#{order.id}")
        return
      end

      if order.processing? && order.may_start_fulfilling?
        order.start_fulfilling!
        notify_fulfilling!(order)
      end
    end

    private

    def minecraft_maintenance_active?
      return false unless Minecraft::MaintenanceActive.pause_fulfillment?

      Minecraft::MaintenanceActive.call.value[:active]
    end

    def handle_fulfillment_result!(order_item, result)
      return true if result.success?

      error = result.error || result.errors&.values&.flatten&.first || "create_fulfillment_failed"
      fulfillment = Commerce::Fulfillment.find_by(order_item: order_item)
      fulfillment&.mark_failed!(error: error)
      Rails.logger.warn("[FulfillOrderJob] Failed to create fulfillment for order_item=#{order_item.id}: #{error}")
      false
    end

    def notify_processing!(order)
      MailDeliveryJob.perform_later("Commerce::OrderMailer", "order_processing", "deliver_now", args: [ order.id ])
      Commerce::InAppNotification.order_event(
        user: order.user,
        notification_type: "commerce.order_processing",
        key: "order_processing",
        order: order
      )
    end

    def notify_fulfilling!(order)
      MailDeliveryJob.perform_later("Commerce::OrderMailer", "order_fulfilling", "deliver_now", args: [ order.id ])
      Commerce::InAppNotification.order_event(
        user: order.user,
        notification_type: "commerce.order_fulfilling",
        key: "order_fulfilling",
        order: order
      )
    end
  end
end
