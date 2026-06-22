# frozen_string_literal: true

module Admin
  module Forum
    class WebhookDeliveriesController < Admin::BaseController
      include Admin::WebhookDeliveryFilterable

      before_action -> { require_admin_module!("system") }
      before_action -> { require_permission("system.settings.manage") }
      before_action :set_delivery, only: %i[show retry]

      def index
        scope = Community::SavedSearchWebhookDelivery.includes(saved_search: :user).recent
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(event_type: params[:event]) if params[:event].present?
        scope = apply_webhook_kind_scope(scope)
        scope = apply_webhook_date_scope(scope)
        @pagy, deliveries = pagy(:offset, scope, limit: 50)

        render inertia: "Admin/Generic/Index", props: {
          title: t("mcweb.admin.forum.webhook_deliveries.title"),
          statusTabs: webhook_status_tabs,
          eventTabs: webhook_event_tabs,
          kindTabs: webhook_kind_tabs,
          dateFilter: webhook_date_filter_props,
          bulkRetry: bulk_retry_props(deliveries),
          columns: [
            admin_column(:search, t("mcweb.admin.forum.webhook_deliveries.col_search"), link: true),
            admin_column(:user, t("mcweb.admin.forum.webhook_deliveries.col_user")),
            admin_column(:status, t("mcweb.admin.store.webhook_deliveries.col_status")),
            admin_column(:code, t("mcweb.admin.store.webhook_deliveries.col_code")),
            admin_column(:attempts, t("mcweb.admin.store.webhook_deliveries.col_attempts")),
            admin_column(:created_at, t("mcweb.admin.store.webhook_deliveries.col_created_at"))
          ],
          rows: deliveries.map { |delivery| serialize_index_row(delivery) },
          pagination: pagy_props(@pagy)
        }
      end

      def show
        render inertia: "Admin/Generic/Show", props: {
          title: t("mcweb.admin.forum.webhook_deliveries.show_title", id: @delivery.id),
          subtitle: @delivery.saved_search&.name,
          fields: [
            { label: t("mcweb.admin.forum.webhook_deliveries.field_user"), value: @delivery.saved_search&.user&.username },
            { label: t("mcweb.admin.store.webhook_deliveries.field_status"), value: webhook_delivery_status_label(@delivery.status) },
            { label: t("mcweb.admin.forum.webhook_deliveries.field_event"), value: @delivery.event_type },
            { label: t("mcweb.admin.forum.webhook_deliveries.field_response_code"), value: @delivery.response_code&.to_s || t("mcweb.labels.not_available") },
            { label: t("mcweb.admin.forum.webhook_deliveries.field_attempt_count"), value: @delivery.attempt_count.to_s },
            { label: t("mcweb.admin.forum.webhook_deliveries.field_url"), value: @delivery.url },
            { label: t("mcweb.admin.forum.webhook_deliveries.field_time"), value: l(@delivery.created_at, format: :short) }
          ],
          preformattedSections: preformatted_sections,
          actions: show_actions,
          backUrl: admin_forum_webhook_deliveries_path(status: params[:status])
        }
      end

      def retry
        result = Community::AdminRetrySavedSearchWebhook.call(delivery: @delivery)
        if result.success?
          redirect_to admin_forum_webhook_delivery_path(@delivery), notice: t("mcweb.flash.webhook_requeued")
        else
          redirect_to admin_forum_webhook_delivery_path(@delivery), alert: service_error_message(result)
        end
      end

      def bulk_retry
        result = Community::BulkRetrySavedSearchWebhooks.call(delivery_ids: params[:ids])
        if result.success?
          redirect_to admin_forum_webhook_deliveries_path(webhook_filter_params),
                      notice: t("mcweb.flash.webhook_retry_queued", count: result.value[:queued])
        else
          redirect_to admin_forum_webhook_deliveries_path(webhook_filter_params),
                      alert: service_error_message(result)
        end
      end

    private

      def set_delivery
        @delivery = Community::SavedSearchWebhookDelivery.find(params[:id])
      end

      def webhook_status_tabs
        base_params = webhook_filter_params.except(:status)
        base = admin_forum_webhook_deliveries_path(base_params)
        current = params[:status].to_s
        [
          { label: t("mcweb.admin.forum.filter_all"), href: base, active: current.blank? },
          { label: t("mcweb.admin.forum.webhook_deliveries.status_failed"), href: admin_forum_webhook_deliveries_path(base_params.merge(status: "failed")), active: current == "failed" },
          { label: t("mcweb.admin.forum.webhook_deliveries.status_success"), href: admin_forum_webhook_deliveries_path(base_params.merge(status: "success")), active: current == "success" },
          { label: t("mcweb.admin.forum.webhook_deliveries.status_pending"), href: admin_forum_webhook_deliveries_path(base_params.merge(status: "pending")), active: current == "pending" }
        ]
      end

      def webhook_event_tabs
        base_params = webhook_filter_params.except(:event)
        base = admin_forum_webhook_deliveries_path(base_params)
        current = params[:event].to_s
        [
          { label: t("mcweb.admin.forum.filter_all_events"), href: base, active: current.blank? },
          {
            label: "saved_search.match",
            href: admin_forum_webhook_deliveries_path(base_params.merge(event: "saved_search.match")),
            active: current == "saved_search.match"
          }
        ]
      end

      def webhook_kind_tabs
        base_params = webhook_filter_params.except(:kind)
        base = admin_forum_webhook_deliveries_path(base_params)
        current = params[:kind].to_s
        [
          { label: t("mcweb.admin.forum.filter_all_sources"), href: base, active: current.blank? },
          { label: t("mcweb.admin.forum.webhook_deliveries.kind_test"), href: admin_forum_webhook_deliveries_path(base_params.merge(kind: "test")), active: current == "test" },
          { label: t("mcweb.admin.forum.webhook_deliveries.kind_production"), href: admin_forum_webhook_deliveries_path(base_params.merge(kind: "production")), active: current == "production" }
        ]
      end

      def serialize_index_row(delivery)
        admin_row(
          search: delivery.saved_search&.name || delivery.request_payload&.dig("search_name") || t("mcweb.labels.not_available"),
          user: delivery.saved_search&.user&.username,
          status: webhook_delivery_status_label(delivery.status),
          code: delivery.response_code&.to_s || t("mcweb.labels.not_available"),
          attempts: delivery.attempt_count.to_s,
          created_at: l(delivery.created_at, format: :short),
          url: admin_forum_webhook_delivery_path(delivery, status: params[:status], event: params[:event])
        )
      end

      def preformatted_sections
        sections = []
        if @delivery.request_payload.present?
          sections << {
            title: t("mcweb.admin.forum.webhook_deliveries.section_request_body"),
            content: JSON.pretty_generate(@delivery.request_payload)
          }
        end
        if @delivery.response_body.present?
          sections << {
            title: t("mcweb.admin.forum.webhook_deliveries.section_response_body"),
            content: @delivery.response_body
          }
        end
        sections
      end

      def show_actions
        return [] unless @delivery.status == "failed" && @delivery.request_payload.present?

        [
          {
            label: t("mcweb.admin.forum.webhook_deliveries.action_retry"),
            href: retry_admin_forum_webhook_delivery_path(@delivery),
            method: "post"
          }
        ]
      end

      def bulk_retry_props(deliveries)
        failed_ids = deliveries.select { |d| d.status == "failed" && d.request_payload.present? }.map(&:id)
        return nil if failed_ids.empty?

        {
          label: t("mcweb.admin.forum.webhook_deliveries.bulk_retry_label", count: failed_ids.size),
          href: bulk_retry_admin_forum_webhook_deliveries_path(webhook_filter_params),
          ids: failed_ids
        }
      end
    end
  end
end
