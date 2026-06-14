# frozen_string_literal: true

module Admin
  class AuditLogsController < BaseController
    before_action -> { require_permission("system.audit.read") }

    def index
      logs = AuditLog.recent
      logs = logs.by_action(params[:action_filter]) if params[:action_filter].present?

      render inertia: "Admin/Generic/Index", props: {
        title: "审计日志",
        columns: [
          admin_column(:action, "操作", link: true),
          admin_column(:actor, "操作者"),
          admin_column(:time, "时间")
        ],
        rows: logs.limit(100).map do |log|
          admin_row(
            action: log.action,
            actor: log.actor&.username,
            time: l(log.created_at, format: :short),
            url: admin_audit_log_path(log)
          )
        end
      }
    end

    def show
      @audit_log = AuditLog.find(params[:id])

      render inertia: "Admin/Generic/Show", props: {
        title: @audit_log.action,
        fields: [
          { label: "操作者", value: @audit_log.actor&.username || "—" },
          { label: "资源", value: "#{@audit_log.resource_type} ##{@audit_log.resource_id}" },
          { label: "IP", value: @audit_log.ip_address || "—" },
          { label: "User agent", value: @audit_log.user_agent || "—" },
          { label: "时间", value: l(@audit_log.created_at, format: :long) }
        ],
        preformatted: if @audit_log.metadata.present?
                        {
                          title: "Metadata",
                          content: JSON.pretty_generate(@audit_log.metadata)
                        }
                      end,
        backUrl: admin_audit_logs_path
      }
    end
  end
end
