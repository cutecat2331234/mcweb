# frozen_string_literal: true

module Admin
  class DashboardController < BaseController
    def index
      metrics_result = Commerce::SalesMetrics.call if show_store_dashboard?
      metrics_data = metrics_result&.value
      webhook_stats = show_store_dashboard? || show_forum_dashboard? || show_system_dashboard? ? WebhookDeliveryStats.summary : {}
      failed_since = 24.hours.ago.to_date.to_s
      health = show_minecraft_dashboard? ? Operations::HealthChecker.call : nil
      mc_check = health&.value&.dig(:checks, :minecraft_nodes)
      show_webhooks = show_store_dashboard? || show_forum_dashboard? || show_system_dashboard?

      render inertia: "Admin/Dashboard/Index", props: {
        metrics: dashboard_metrics(metrics_data),
        minecraftHealth: mc_check ? {
          status: mc_check[:status],
          nodes: mc_check[:nodes],
          managed_servers: mc_check[:managed_servers],
          stale_online_nodes: mc_check[:stale_online_nodes],
          process_mismatch_servers: mc_check[:process_mismatch_servers],
          message: mc_check[:message]
        } : nil,
        webhookStats: {
          forum: show_webhooks ? webhook_stats[:forum] : nil,
          store: show_webhooks ? webhook_stats[:store] : nil,
          storeByEvent: show_webhooks ? webhook_stats[:store_by_event] : nil
        },
        webhookFailedLinks: {
          forum: show_webhooks ? admin_forum_webhook_deliveries_path(status: "failed", created_from: failed_since) : nil,
          store: show_webhooks ? admin_store_webhook_deliveries_path(status: "failed", created_from: failed_since) : nil
        },
        recentAuditLogs: show_system_dashboard? ? AuditLog.recent.limit(10).map do |log|
          {
            action: log.action,
            actor: log.actor&.username,
            created_at: l(log.created_at, format: :short)
          }
        end : []
      }
    end

    private

    def show_store_dashboard?
      current_user.account_type.in?(%w[owner admin]) || current_user.admin_module_allowed?("store")
    end

    def show_forum_dashboard?
      current_user.account_type.in?(%w[owner admin]) || current_user.admin_module_allowed?("forum")
    end

    def show_minecraft_dashboard?
      current_user.account_type.in?(%w[owner admin]) || current_user.admin_module_allowed?("minecraft")
    end

    def show_system_dashboard?
      current_user.account_type.in?(%w[owner admin]) || current_user.admin_module_allowed?("system")
    end

    def dashboard_metrics(metrics_data)
      metrics = []
      if show_system_dashboard?
        metrics << { label: t("mcweb.admin.dashboard.metrics.users"), value: User.count }
      end
      if show_forum_dashboard?
        metrics << { label: t("mcweb.admin.dashboard.metrics.pending_reports"), value: Community::Report.pending_review.count }
      end
      return metrics unless show_store_dashboard? && metrics_data

      metrics + [
        { label: t("mcweb.admin.dashboard.metrics.orders"), value: Commerce::Order.count },
        { label: t("mcweb.admin.dashboard.metrics.total_revenue"), value: format("%.2f", metrics_data[:revenue_cents] / 100.0) },
        { label: t("mcweb.admin.dashboard.metrics.revenue_7d"), value: format("%.2f", metrics_data[:revenue_7d_cents] / 100.0) },
        { label: t("mcweb.admin.dashboard.metrics.aov"), value: format("%.2f", metrics_data[:aov_cents] / 100.0) },
        { label: t("mcweb.admin.dashboard.metrics.pending_orders"), value: metrics_data[:pending_count] },
        { label: t("mcweb.admin.dashboard.metrics.low_stock_products"), value: metrics_data[:low_stock_count] },
        { label: t("mcweb.admin.dashboard.metrics.refunds_7d"), value: metrics_data[:refund_count_7d] },
        { label: t("mcweb.admin.dashboard.metrics.abandoned_carts"), value: metrics_data[:abandoned_carts_count] }
      ]
    end
  end
end
