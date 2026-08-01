# frozen_string_literal: true

require "csv"

module Admin
  class AuditLogsController < BaseController
    before_action -> { require_admin_module!("system") }
    before_action -> { require_permission("system.audit.read") }
    before_action -> { require_permission("system.audit.export") }, only: :export

    def index
      query = audit_query

      render inertia: "Admin/AuditLogs/Index", props: {
        rows: query.records.map { |log| serialize_log(log) },
        filters: query.filters,
        filterErrors: query.errors,
        pagination: {
          page: query.page,
          perPage: query.per_page,
          total: query.total,
          totalPages: query.total_pages
        },
        canExport: current_user.permission?("system.audit.export"),
        exportUrl: export_admin_audit_logs_path,
        resourceTypes: AuditLog.where.not(resource_type: nil)
          .distinct
          .order(:resource_type)
          .limit(100)
          .pluck(:resource_type)
      }
    end

    def show
      log = AuditLog.includes(:actor).find(params[:id])

      render inertia: "Admin/AuditLogs/Show", props: {
        log: serialize_log(log).merge(
          ipAddress: log.ip_address,
          userAgent: log.user_agent,
          beforeState: log.before_state,
          afterState: log.after_state,
          metadata: log.metadata
        ),
        backUrl: admin_audit_logs_path
      }
    end

    def export
      query = audit_query
      logs = query.relation.includes(:actor).limit(Administration::AuditLogQuery::MAX_EXPORT_ROWS + 1).to_a
      if logs.size > Administration::AuditLogQuery::MAX_EXPORT_ROWS
        return redirect_to admin_audit_logs_path(audit_route_filters(query.filters)),
                           alert: t("mcweb.admin.audit.export_too_large")
      end

      csv = build_csv(logs)
      Administration::AuditLogger.call(
        actor: current_user,
        action: "system.audit.exported",
        metadata: {
          filters: query.filters.compact_blank,
          exported_count: logs.size
        },
        request_id: request.request_id,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      response.set_header("Cache-Control", "private, no-store")
      send_data csv,
                type: "text/csv; charset=utf-8",
                disposition: "attachment",
                filename: "mcweb-audit-#{Time.current.utc.strftime('%Y%m%d-%H%M%S')}.csv"
    end

    private

    def audit_query
      @audit_query ||= Administration::AuditLogQuery.new(
        filters: audit_filter_params,
        page: params[:page],
        per_page: params[:per_page]
      )
    end

    def audit_filter_params
      filters = params
        .permit(:event_action, :action_filter, :actor, :resource_type, :resource, :request_id, :from, :to)
        .to_h
      filters["action"] = filters.delete("event_action").presence ||
        filters.delete("action_filter").presence
      filters
    end

    def audit_route_filters(filters)
      filters.except(:action).merge(event_action: filters[:action]).compact_blank
    end

    def serialize_log(log)
      {
        id: log.id,
        actionLabel: audit_action_label(log.action),
        actionCode: log.action,
        actor: log.actor && {
          username: log.actor.username,
          publicId: log.actor.public_id
        },
        resource: {
          type: log.resource_type,
          typeLabel: resource_type_label(log.resource_type),
          id: log.resource_id,
          publicId: log.resource_public_id
        },
        requestId: log.request_id,
        reason: log.reason,
        occurredAt: I18n.l(log.created_at, format: :long),
        occurredAtIso: log.created_at.iso8601,
        showUrl: admin_audit_log_path(log)
      }
    end

    def audit_action_label(action)
      Administration::AuditActionLabel.call(action)
    end

    def resource_type_label(resource_type)
      return t("mcweb.labels.not_available") if resource_type.blank?

      resource_type.to_s.demodulize.underscore.humanize
    end

    def build_csv(logs)
      bom = "\uFEFF"
      body = CSV.generate do |csv|
        csv << %i[
          id occurred_at action action_code actor actor_public_id resource_type
          resource_identifier request_id reason metadata
        ].map { |key| t("mcweb.admin.audit.csv.#{key}") }
        logs.each do |log|
          csv << [
            log.id,
            log.created_at.iso8601,
            audit_action_label(log.action),
            log.action,
            log.actor&.username,
            log.actor&.public_id,
            resource_type_label(log.resource_type),
            log.resource_public_id.presence || log.resource_id,
            log.request_id,
            log.reason,
            JSON.generate(log.metadata)
          ]
        end
      end
      bom + body
    end
  end
end
