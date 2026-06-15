# frozen_string_literal: true

module Admin
  module Store
    class WebhookDeliveriesController < BaseController
      before_action -> { require_permission("system.settings.manage") }

      def index
        scope = Commerce::OrderWebhookDelivery.order(created_at: :desc)
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(event_type: params[:event]) if params[:event].present?
        @pagy, deliveries = pagy(scope, limit: 50)

        render inertia: "Admin/Generic/Index", props: {
          title: "订单 Webhook 投递",
          statusTabs: webhook_status_tabs,
          columns: [
            admin_column(:order, "订单"),
            admin_column(:event, "事件"),
            admin_column(:status, "状态"),
            admin_column(:code, "响应码"),
            admin_column(:attempts, "尝试"),
            admin_column(:created_at, "时间")
          ],
          rows: deliveries.map { |delivery| serialize_index_row(delivery) },
          pagination: pagy_props(@pagy)
        }
      end

    private

      def webhook_status_tabs
        base = admin_store_webhook_deliveries_path
        current = params[:status].to_s
        [
          { label: "全部", href: base, active: current.blank? },
          { label: "失败", href: "#{base}?status=failed", active: current == "failed" },
          { label: "成功", href: "#{base}?status=success", active: current == "success" },
          { label: "进行中", href: "#{base}?status=pending", active: current == "pending" }
        ]
      end

      def serialize_index_row(delivery)
        admin_row(
          order: delivery.order_public_id.presence || "—",
          event: delivery.event_type,
          status: delivery.status,
          code: delivery.response_code&.to_s || "—",
          attempts: delivery.attempt_count.to_s,
          created_at: l(delivery.created_at, format: :short)
        )
      end
    end
  end
end
