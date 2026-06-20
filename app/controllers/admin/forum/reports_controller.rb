# frozen_string_literal: true

module Admin
  module Forum
    class ReportsController < BaseController
      before_action -> { require_permission("forum.topics.lock") }
      before_action :set_report, only: %i[show update]

      def index
        reports = ::Community::Report.pending_review.order(created_at: :desc)

        render inertia: "Admin/Generic/Index", props: {
          title: forum_t("reports.title"),
          columns: [
            admin_column(:reason, forum_t("reports.col_reason"), link: true),
            admin_column(:reporter, forum_t("reports.col_reporter")),
            admin_column(:status, forum_t("reports.col_status")),
            admin_column(:time, forum_t("reports.col_time"))
          ],
          rows: reports.map do |report|
            admin_row(
              reason: report.reason_label.present? ? "#{report.reason_label} — #{report.reason.truncate(40)}" : report.reason.truncate(60),
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
          title: forum_t("reports.show_title"),
          fields: [
            { label: forum_t("reports.field_type"), value: @report.reason_label || forum_na },
            { label: forum_t("reports.field_reason"), value: @report.reason },
            { label: forum_t("reports.field_reporter"), value: @report.reporter&.username || forum_na },
            { label: forum_t("reports.field_status"), value: @report.status },
            { label: forum_t("reports.field_target"), value: reportable_label },
            { label: forum_t("reports.field_time"), value: l(@report.created_at, format: :long) }
          ],
          backUrl: admin_forum_reports_path,
          actions: report_actions + reportable_actions
        }
      end

      def update
        status = report_params[:status].presence || params[:status].presence || "reviewed"
        @report.review!(
          reviewer: current_user,
          note: report_params[:review_note],
          status: status.to_sym
        )

        Administration::AuditLogger.call(
          actor: current_user,
          action: "admin.forum_report_reviewed",
          resource: @report
        )

        Community::ClearReportableHide.call(reportable: @report.reportable) if @report.dismissed?

        redirect_to admin_forum_report_path(@report), notice: t("mcweb.flash.report_resolved")
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_forum_report_path(@report), alert: e.record.errors.full_messages.to_sentence
      end

      private

      def set_report
        @report = ::Community::Report.find(params[:id])
      end

      def report_params
        params.fetch(:report, {}).permit(:status, :review_note)
      end

      def report_actions
        return [] unless @report.pending?

        [
          {
            label: forum_t("reports.action_reviewed"),
            href: admin_forum_report_path(@report),
            method: "patch",
            data: { report: { status: "reviewed" } }
          },
          {
            label: forum_t("reports.action_dismiss"),
            href: admin_forum_report_path(@report),
            method: "patch",
            variant: "outline",
            data: { report: { status: "dismissed" } }
          }
        ]
      end

      def reportable_label
        case @report.reportable
        when ::Community::Topic
          forum_t("reports.target_topic", title: @report.reportable.title)
        when ::Community::Post
          forum_t("reports.target_post", floor: @report.reportable.floor_number, title: @report.reportable.topic.title)
        when ::Commerce::Review
          forum_t("reports.target_review", id: @report.reportable.id, product: @report.reportable.product.name)
        else
          "#{@report.reportable_type} ##{@report.reportable_id}"
        end
      end

      def reportable_actions
        case @report.reportable
        when ::Community::Topic
          [ { label: forum_t("reports.action_view_topic"), href: forum_topic_path(@report.reportable) } ]
        when ::Community::Post
          [ { label: forum_t("reports.action_view_post"), href: "#{forum_topic_path(@report.reportable.topic)}#post-#{@report.reportable.id}" } ]
        when ::Commerce::Review
          [ { label: forum_t("reports.action_view_product"), href: store_product_path(@report.reportable.product) } ]
        else
          []
        end
      end
    end
  end
end
