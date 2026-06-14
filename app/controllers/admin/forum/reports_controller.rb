# frozen_string_literal: true

module Admin
  module Forum
    class ReportsController < BaseController
      before_action -> { require_permission("forum.topics.lock") }
      before_action :set_report, only: %i[show update]

      def index
        reports = ::Community::Report.pending_review.order(created_at: :desc)

        render inertia: "Admin/Generic/Index", props: {
          title: "内容举报",
          columns: [
            admin_column(:reason, "原因", link: true),
            admin_column(:reporter, "举报人"),
            admin_column(:status, "状态"),
            admin_column(:time, "时间")
          ],
          rows: reports.map do |report|
            admin_row(
              reason: report.reason.truncate(60),
              reporter: report.reporter&.username,
              status: report.status,
              time: l(report.created_at, format: :short),
              url: admin_forum_report_path(report)
            )
          end
        }
      end

      def show
        render inertia: "Admin/Generic/Show", props: {
          title: "举报详情",
          fields: [
            { label: "原因", value: @report.reason },
            { label: "举报人", value: @report.reporter&.username || "—" },
            { label: "状态", value: @report.status },
            { label: "对象", value: "#{@report.reportable_type} ##{@report.reportable_id}" },
            { label: "时间", value: l(@report.created_at, format: :long) }
          ],
          backUrl: admin_forum_reports_path
        }
      end

      def update
        status = report_params[:status].presence&.to_sym || :reviewed
        @report.review!(
          reviewer: current_user,
          note: report_params[:review_note],
          status: status
        )

        Administration::AuditLogger.call(
          actor: current_user,
          action: "admin.forum_report_reviewed",
          resource: @report
        )

        redirect_to admin_forum_report_path(@report), notice: "Report reviewed."
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_forum_report_path(@report), alert: e.record.errors.full_messages.to_sentence
      end

      private

      def set_report
        @report = ::Community::Report.find(params[:id])
      end

      def report_params
        params.expect(report: %i[status review_note])[:report]
      end
    end
  end
end
