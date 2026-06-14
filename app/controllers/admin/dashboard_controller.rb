# frozen_string_literal: true

module Admin
  class DashboardController < BaseController
    def index
      render inertia: "Admin/Dashboard/Index", props: {
        metrics: [
          { label: "用户", value: User.count },
          { label: "订单", value: Commerce::Order.count },
          { label: "待处理举报", value: Community::Report.pending_review.count }
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
