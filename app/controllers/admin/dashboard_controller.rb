# frozen_string_literal: true

module Admin
  class DashboardController < BaseController
    def index
      metrics_result = Commerce::SalesMetrics.call
      metrics_data = metrics_result.value

      render inertia: "Admin/Dashboard/Index", props: {
        metrics: [
          { label: "用户", value: User.count },
          { label: "订单", value: Commerce::Order.count },
          { label: "待处理举报", value: Community::Report.pending_review.count },
          { label: "总营收 (¥)", value: format("%.2f", metrics_data[:revenue_cents] / 100.0) },
          { label: "7日营收 (¥)", value: format("%.2f", metrics_data[:revenue_7d_cents] / 100.0) },
          { label: "客单价 (¥)", value: format("%.2f", metrics_data[:aov_cents] / 100.0) },
          { label: "待支付订单", value: metrics_data[:pending_count] },
          { label: "低库存商品", value: metrics_data[:low_stock_count] },
          { label: "7日退款", value: metrics_data[:refund_count_7d] },
          { label: "弃购购物车", value: metrics_data[:abandoned_carts_count] }
        ],
        recentAuditLogs: AuditLog.recent.limit(10).map do |log|
          {
            action: log.action,
            actor: log.actor&.username,
            created_at: l(log.created_at, format: :short)
          }
        end
      }
    end
  end
end
