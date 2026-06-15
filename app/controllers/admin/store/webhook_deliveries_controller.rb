# frozen_string_literal: true

module Admin
  module Store
    class WebhookDeliveriesController < BaseController
      before_action -> { require_permission("system.settings.manage") }
      before_action :set_delivery, only: %i[show retry]

      def index
        scope = Commerce::OrderWebhookDelivery.order(created_at: :desc)
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(event_type: params[:event]) if params[:event].present?
        @pagy, deliveries = pagy(scope, limit: 50)

        render inertia: "Admin/Generic/Index", props: {
          title: "订单 Webhook 投递",
          statusTabs: webhook_status_tabs,
          eventTabs: webhook_event_tabs,
          columns: [
            admin_column(:order, "订单", link: true),
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

      def show
        render inertia: "Admin/Generic/Show", props: {
          title: "订单 Webhook 投递 ##{@delivery.id}",
          subtitle: @delivery.order_public_id,
          fields: [
            { label: "订单", value: @delivery.order_public_id.presence || "—" },
            { label: "状态", value: @delivery.status },
            { label: "事件", value: @delivery.event_type },
            { label: "响应码", value: @delivery.response_code&.to_s || "—" },
            { label: "尝试次数", value: @delivery.attempt_count.to_s },
            { label: "URL", value: @delivery.url },
            { label: "时间", value: l(@delivery.created_at, format: :short) }
          ],
          preformattedSections: preformatted_sections,
          actions: show_actions,
          backUrl: admin_store_webhook_deliveries_path(status: params[:status], event: params[:event])
        }
      end

      def retry
        result = Commerce::AdminRetryOrderWebhook.call(delivery: @delivery)
        if result.success?
          redirect_to admin_store_webhook_delivery_path(@delivery), notice: "Webhook 已重新加入发送队列。"
        else
          redirect_to admin_store_webhook_delivery_path(@delivery), alert: result.error || "重试失败。"
        end
      end

    private

      def set_delivery
        @delivery = Commerce::OrderWebhookDelivery.find(params[:id])
      end

      def webhook_status_tabs
        base_params = { event: params[:event].presence }.compact
        base = admin_store_webhook_deliveries_path(base_params)
        current = params[:status].to_s
        [
          { label: "全部", href: base, active: current.blank? },
          { label: "失败", href: admin_store_webhook_deliveries_path(base_params.merge(status: "failed")), active: current == "failed" },
          { label: "成功", href: admin_store_webhook_deliveries_path(base_params.merge(status: "success")), active: current == "success" },
          { label: "进行中", href: admin_store_webhook_deliveries_path(base_params.merge(status: "pending")), active: current == "pending" }
        ]
      end

      def webhook_event_tabs
        base_params = { status: params[:status].presence }.compact
        base = admin_store_webhook_deliveries_path(base_params)
        current = params[:event].to_s
        events = %w[order.created order.paid order.status_changed order.shipped order.test]
        tabs = [{ label: "全部事件", href: base, active: current.blank? }]
        events.each do |event|
          tabs << {
            label: event,
            href: admin_store_webhook_deliveries_path(base_params.merge(event: event)),
            active: current == event
          }
        end
        tabs
      end

      def serialize_index_row(delivery)
        admin_row(
          order: delivery.order_public_id.presence || "—",
          event: delivery.event_type,
          status: delivery.status,
          code: delivery.response_code&.to_s || "—",
          attempts: delivery.attempt_count.to_s,
          created_at: l(delivery.created_at, format: :short),
          url: admin_store_webhook_delivery_path(delivery, status: params[:status], event: params[:event])
        )
      end

      def preformatted_sections
        sections = []
        if @delivery.request_payload.present?
          sections << {
            title: "请求体",
            content: JSON.pretty_generate(@delivery.request_payload)
          }
        end
        if @delivery.response_body.present?
          sections << {
            title: "响应体",
            content: @delivery.response_body
          }
        end
        sections
      end

      def show_actions
        return [] unless @delivery.status == "failed" && @delivery.request_payload.present?

        [
          {
            label: "重试发送",
            href: retry_admin_store_webhook_delivery_path(@delivery),
            method: "post"
          }
        ]
      end
    end
  end
end
