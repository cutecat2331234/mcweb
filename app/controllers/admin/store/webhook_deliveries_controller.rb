# frozen_string_literal: true

module Admin
  module Store
    class WebhookDeliveriesController < BaseController
      include Admin::WebhookDeliveryFilterable

      before_action -> { require_permission("system.settings.manage") }
      before_action :set_delivery, only: %i[show retry]

      def index
        scope = Commerce::OrderWebhookDelivery.order(created_at: :desc)
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(event_type: params[:event]) if params[:event].present?
        scope = apply_webhook_kind_scope(scope)
        scope = apply_webhook_date_scope(scope)
        @pagy, deliveries = pagy(scope, limit: 50)

        render inertia: "Admin/Generic/Index", props: {
          title: "订单 Webhook 投递",
          statusTabs: webhook_status_tabs,
          eventTabs: webhook_event_tabs,
          kindTabs: webhook_kind_tabs,
          dateFilter: webhook_date_filter_props,
          bulkRetry: bulk_retry_props(deliveries),
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
          redirect_to admin_store_webhook_delivery_path(@delivery), notice: t("mcweb.flash.webhook_requeued")
        else
          redirect_to admin_store_webhook_delivery_path(@delivery), alert: result.error || t("mcweb.flash.webhook_retry_failed")
        end
      end

      def bulk_retry
        result = Commerce::BulkRetryOrderWebhooks.call(delivery_ids: params[:ids])
        if result.success?
          redirect_to admin_store_webhook_deliveries_path(webhook_filter_params),
                      notice: t("mcweb.flash.webhook_retry_queued", count: result.value[:queued])
        else
          redirect_to admin_store_webhook_deliveries_path(webhook_filter_params),
                      alert: result.error || t("mcweb.flash.webhook_batch_retry_failed")
        end
      end

    private

      def set_delivery
        @delivery = Commerce::OrderWebhookDelivery.find(params[:id])
      end

      def webhook_status_tabs
        base_params = webhook_filter_params.except(:status)
        base = admin_store_webhook_deliveries_path(base_params)
        current = params[:status].to_s
        counts = webhook_status_counts_scope.group(:status).count
        total = counts.values.sum
        tabs = [ { label: "全部", href: base, active: current.blank?, count: total } ]
        {
          "failed" => "失败",
          "success" => "成功",
          "pending" => "进行中"
        }.each do |status, label|
          count = counts[status].to_i
          next if count.zero? && current != status

          tabs << {
            label: label,
            href: admin_store_webhook_deliveries_path(base_params.merge(status: status)),
            active: current == status,
            count: count
          }
        end
        tabs
      end

      def webhook_counts_scope
        scope = Commerce::OrderWebhookDelivery.all
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(event_type: params[:event]) if params[:event].present?
        scope = apply_webhook_kind_scope(scope)
        apply_webhook_date_scope(scope)
      end

      def webhook_status_counts_scope
        scope = Commerce::OrderWebhookDelivery.all
        scope = scope.where(event_type: params[:event]) if params[:event].present?
        scope = apply_webhook_kind_scope(scope)
        apply_webhook_date_scope(scope)
      end

      def webhook_event_counts_scope
        scope = Commerce::OrderWebhookDelivery.all
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = apply_webhook_kind_scope(scope)
        apply_webhook_date_scope(scope)
      end

      def webhook_event_tabs
        base_params = webhook_filter_params.except(:event)
        base = admin_store_webhook_deliveries_path(base_params)
        current = params[:event].to_s
        counts = webhook_event_counts_scope.group(:event_type).count
        total = counts.values.sum
        events = %w[order.created order.paid order.status_changed order.shipped order.fulfilled order.cancelled order.refunded order.test]
        tabs = [ { label: "全部事件", href: base, active: current.blank?, count: total } ]
        events.each do |event|
          count = counts[event].to_i
          next if count.zero? && current != event

          tabs << {
            label: event,
            href: admin_store_webhook_deliveries_path(base_params.merge(event: event)),
            active: current == event,
            count: count
          }
        end
        tabs
      end

      def webhook_kind_tabs
        base_params = webhook_filter_params.except(:kind)
        base = admin_store_webhook_deliveries_path(base_params)
        current = params[:kind].to_s
        [
          { label: "全部来源", href: base, active: current.blank? },
          { label: "测试", href: admin_store_webhook_deliveries_path(base_params.merge(kind: "test")), active: current == "test" },
          { label: "正式", href: admin_store_webhook_deliveries_path(base_params.merge(kind: "production")), active: current == "production" }
        ]
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

      def bulk_retry_props(deliveries)
        failed_ids = deliveries.select { |d| d.status == "failed" && d.request_payload.present? }.map(&:id)
        return nil if failed_ids.empty?

        {
          label: "重试本页失败项 (#{failed_ids.size})",
          href: bulk_retry_admin_store_webhook_deliveries_path(webhook_filter_params),
          ids: failed_ids
        }
      end
    end
  end
end
