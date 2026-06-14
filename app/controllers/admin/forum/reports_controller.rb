# frozen_string_literal: true

module Admin
  module Forum
    class ReportsController < BaseController
      before_action -> { require_permission("forum.topics.lock") }
      before_action :set_report, only: %i[show update]

      def index
        @reports = ::Community::Report.pending_review.order(created_at: :desc)
      end

      def show
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
