# frozen_string_literal: true

module Admin
  module Store
    class PaymentOperationsController < BaseController
      PER_PAGE = 40

      before_action -> { require_permission("store.orders.read") }
      before_action -> { require_permission(Payments::ReplayWebhookEvent::PERMISSION) },
        only: :replay

      def index
        query = Payments::OperationsQuery.new(
          view: params[:view],
          provider: params[:provider],
          status: params[:status],
          provider_status: params[:provider_status],
          query: params[:q]
        )
        @pagy, records = pagy(:offset, query.relation, limit: PER_PAGE)

        response.set_header("Cache-Control", "no-store")
        render inertia: "Admin/Store/PaymentOperations/Index", props: {
          view: query.view,
          filters: Payments::OperationsSerializer.filters(query.filters),
          filterOptions: Payments::OperationsSerializer.filter_options(query.filter_options),
          summary: query.summary,
          providerStatuses: query.provider_statuses.map do |status|
            Payments::OperationsSerializer.provider_status(status)
          end,
          rows: serialize_rows(query.view, records),
          pagination: pagy_props(@pagy),
          replayEnabled: current_user.permission?(Payments::ReplayWebhookEvent::PERMISSION)
        }
      end

      def replay
        event = Payments::WebhookEvent.find(params[:id])
        result = Payments::ReplayWebhookEvent.call(
          event: event,
          actor: current_user,
          token: params[:token],
          reason: params[:reason]
        )

        if result.success?
          redirect_to admin_store_payment_operations_path(view: "webhooks"),
            notice: t(
              "mcweb.flash.payment_webhook_replay_queued",
              default: "Payment webhook replay queued."
            )
        else
          redirect_to admin_store_payment_operations_path(view: "webhooks"),
            alert: result.error
        end
      end

      private

      def serialize_rows(view, records)
        case view
        when "webhooks"
          records.map { |event| serialize_webhook(event) }
        when "refunds"
          records.map { |refund| Payments::OperationsSerializer.refund(refund) }
        else
          records.map { |payment| Payments::OperationsSerializer.record(payment) }
        end
      end

      def serialize_webhook(event)
        serialized = Payments::OperationsSerializer.webhook(event)
        return serialized unless current_user.permission?(Payments::ReplayWebhookEvent::PERMISSION)
        return serialized unless event.manually_replayable?

        serialized.merge(
          replay: {
            url: admin_store_payment_webhook_replay_path(event),
            token: Payments::WebhookReplayToken.issue(event)
          }
        )
      end
    end
  end
end
