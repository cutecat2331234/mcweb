# frozen_string_literal: true

module Commerce
  module Disputes
    class CustomerNotifier < ApplicationService
      NOTIFICATION_TYPE = "commerce.payment_dispute_update"
      CUSTOMER_EVENT_TYPES = %w[
        customer_opened customer_withdrawn customer_refund_resolved
      ].freeze
      PUBLIC_EVENT_KINDS = %w[
        provider_opened provider_bound status_changed rights_changed
      ].freeze

      def initialize(event:)
        @event = event
      end

      def call
        return ServiceResult.success(skipped: true) unless public_event?

        user = @event.dispute.order.user
        return ServiceResult.success(skipped: true) unless user
        unless NotificationPreference.enabled?(
          user,
          channel: "in_app",
          notification_type: NOTIFICATION_TYPE
        )
          return ServiceResult.success(skipped: true)
        end

        notification = nil
        idempotent = false
        Notification.transaction do
          acquire_event_lock!
          notification = existing_notification(user)
          if notification
            idempotent = true
            next
          end

          Commerce::InAppNotification.with_recipient_locale(user) do
            notification = Notification.notify!(
              user: user,
              notification_type: NOTIFICATION_TYPE,
              title: notification_title,
              body: notification_body,
              metadata: {
                path: order_path,
                order_public_id: @event.dispute.order.public_id,
                dispute_public_id: @event.dispute.public_id,
                commerce_dispute_event_key: event_key
              }
            )
          end
        end

        ServiceResult.success(notification:, idempotent:)
      rescue ActiveRecord::RecordInvalid => error
        ServiceResult.failure(errors: error.record.errors.to_hash)
      end

      private

      def public_event?
        CUSTOMER_EVENT_TYPES.include?(@event.event_type) ||
          PUBLIC_EVENT_KINDS.include?(@event.metadata["customer_event_kind"])
      end

      def existing_notification(user)
        Notification.where(
          user: user,
          notification_type: NOTIFICATION_TYPE
        ).find_by("metadata ->> 'commerce_dispute_event_key' = ?", event_key)
      end

      def acquire_event_lock!
        lock_key = event_key.first(15).to_i(16)
        query = ActiveRecord::Base.sanitize_sql_array(
          [ "SELECT pg_advisory_xact_lock(?)::text", lock_key ]
        )
        Notification.connection.select_value(query)
      end

      def event_key
        @event_key ||= Digest::SHA256.hexdigest(@event.idempotency_key)
      end

      def notification_body
        I18n.t(
          "mcweb.commerce.payment_disputes.notifications.#{notification_key}.body",
          number: @event.dispute.order.order_number,
          status: status_label,
          rights_status: rights_status_label
        )
      end

      def notification_title
        labels = I18n.t("mcweb.labels.notification_types", default: {})
        return NOTIFICATION_TYPE.humanize unless labels.is_a?(Hash)

        labels[NOTIFICATION_TYPE.to_sym].presence ||
          labels[NOTIFICATION_TYPE].presence ||
          NOTIFICATION_TYPE.humanize
      end

      def notification_key
        return @event.event_type if CUSTOMER_EVENT_TYPES.include?(@event.event_type)
        return "evidence_required" if @event.to_status == "evidence_required"
        event_kind = @event.metadata["customer_event_kind"].to_s
        return event_kind if PUBLIC_EVENT_KINDS.include?(event_kind)

        "status_changed"
      end

      def status_label
        I18n.t(
          "mcweb.commerce.payment_disputes.statuses.#{@event.to_status}",
          default: @event.to_status.to_s.humanize
        )
      end

      def rights_status_label
        I18n.t(
          "mcweb.commerce.payment_disputes.rights_statuses.#{@event.metadata['rights_status']}",
          default: @event.metadata["rights_status"].to_s.humanize
        )
      end

      def order_path
        "#{Mcweb::Paths::APP_PREFIX}/store/orders/#{@event.dispute.order.public_id}"
      end
    end
  end
end
