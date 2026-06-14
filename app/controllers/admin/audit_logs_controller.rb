# frozen_string_literal: true

module Admin
  class AuditLogsController < BaseController
    before_action -> { require_permission("admin.audit_logs.view") }

    def index
      @audit_logs = AuditLog.recent
      @audit_logs = @audit_logs.by_action(params[:action_filter]) if params[:action_filter].present?
    end

    def show
      @audit_log = AuditLog.find(params[:id])
    end
  end
end
