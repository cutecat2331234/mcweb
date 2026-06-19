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
          title: "举报详情",
          fields: [
            { label: "类型", value: @report.reason_label || "—" },
            { label: "原因", value: @report.reason },
            { label: "举报人", value: @report.reporter&.username || "—" },
            { label: "状态", value: @report.status },
            { label: "对象", value: reportable_label },
            { label: "时间", value: l(@report.created_at, format: :long) }
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

        redirect_to admin_forum_report_path(@report), notice: "举报已处理。"
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
            label: "标记已审核",
            href: admin_forum_report_path(@report),
            method: "patch",
            data: { report: { status: "reviewed" } }
          },
          {
            label: "驳回举报",
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
          "主题：#{@report.reportable.title}"
        when ::Community::Post
          "帖子 ##{@report.reportable.floor_number}（#{@report.reportable.topic.title}）"
        when ::Commerce::Review
          "评价 ##{@report.reportable.id}（#{@report.reportable.product.name}）"
        else
          "#{@report.reportable_type} ##{@report.reportable_id}"
        end
      end

      def reportable_actions
        case @report.reportable
        when ::Community::Topic
          [ { label: "查看主题", href: forum_topic_path(@report.reportable) } ]
        when ::Community::Post
          [ { label: "查看帖子", href: "#{forum_topic_path(@report.reportable.topic)}#post-#{@report.reportable.id}" } ]
        when ::Commerce::Review
          [ { label: "查看商品", href: store_product_path(@report.reportable.product) } ]
        else
          []
        end
      end
    end
  end
end
