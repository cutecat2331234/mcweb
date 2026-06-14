# frozen_string_literal: true

module Admin
  class DashboardController < BaseController
    def index
      @users_count = User.count
      @orders_count = Commerce::Order.count
      @pending_reports_count = Community::Report.pending_review.count
      @recent_audit_logs = AuditLog.recent.limit(10)
    end
  end
end
