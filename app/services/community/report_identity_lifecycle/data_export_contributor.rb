# frozen_string_literal: true

module Community
  module ReportIdentityLifecycle
    class DataExportContributor
      class << self
        def call(context:)
          user = context.user
          ::Identity::DataExporting::Contribution.new(
            documents: {
              "forum/report_cases.json" => ::Identity::DataExporting::StreamingObjectDocument.new(
                members: {
                  "submitted_reports" => submitted_reports(user),
                  "appeals" => appeals(user),
                  "account_actions" => account_actions(user)
                }
              )
            }
          )
        end

        private

        def submitted_reports(user)
          scope = Community::Report.where(reporter_id: user.id).order(:id)
          ::Identity::DataExporting::RecordSerializer.stream_relation(scope) do |report|
            {
              "public_id" => report.public_id,
              "target_kind" => Community::ReporterReportSerializer::SAFE_TARGET_KINDS
                .fetch(report.reportable_type, "content"),
              "reason_code" => report.reason_code,
              "reason_detail" => report.reason,
              "status" => report.status,
              "public_outcome_code" => report.public_outcome_code,
              "submitted_at" => timestamp(report.created_at),
              "state_changed_at" => timestamp(report.state_changed_at)
            }.compact
          end
        end

        def appeals(user)
          scope = Community::ReportAppeal
            .where(appellant_id: user.id)
            .includes(:report, :events)
            .order(:id)
          ::Identity::DataExporting::RecordSerializer.stream_relation(scope) do |appeal|
            {
              "public_id" => appeal.public_id,
              "report_public_id" => appeal.report.public_id,
              "appellant_role" => appeal.appellant_role,
              "reason" => appeal.reason,
              "status" => appeal.status,
              "public_outcome_code" => appeal.public_outcome_code,
              "expires_at" => timestamp(appeal.expires_at),
              "submitted_at" => timestamp(appeal.submitted_at),
              "decided_at" => timestamp(appeal.decided_at),
              "cancelled_at" => timestamp(appeal.cancelled_at),
              "events" => appeal.events.sort_by { |event| [ event.occurred_at, event.id ] }.map do |event|
                {
                  "type" => event.event_type,
                  "from_status" => event.from_status,
                  "to_status" => event.to_status,
                  "public_outcome_code" => event.public_outcome_code,
                  "occurred_at" => timestamp(event.occurred_at)
                }.compact
              end
            }.compact
          end
        end

        def account_actions(user)
          scope = Community::Report.where(affected_user_id: user.id).order(:id)
          ::Identity::DataExporting::RecordSerializer.stream_relation(scope) do |report|
            {
              "report_public_id" => report.public_id,
              "status" => report.status,
              "public_outcome_code" => report.public_outcome_code,
              "state_changed_at" => timestamp(report.state_changed_at)
            }.compact
          end
        end

        def timestamp(value)
          value&.iso8601
        end
      end
    end
  end
end
