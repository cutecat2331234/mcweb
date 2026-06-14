# frozen_string_literal: true

module Community
  class ReportsController < ApplicationController
    before_action :require_login

    def create
      reportable = find_reportable
      return redirect_back fallback_location: root_path, alert: "Content not found." unless reportable

      report = Community::Report.create!(
        reporter: current_user,
        reportable: reportable,
        reason: report_params[:reason],
        status: :pending
      )

      Administration::AuditLogger.call(
        actor: current_user,
        action: "community.report_created",
        resource: report
      )

      redirect_back fallback_location: root_path, notice: "Report submitted."
    rescue ActiveRecord::RecordInvalid => e
      redirect_back fallback_location: root_path, alert: e.record.errors.full_messages.to_sentence
    end

    private

    def report_params
      params.expect(report: %i[reportable_type reportable_id reason])[:report]
    end

    def find_reportable
      type = report_params[:reportable_type]
      return unless %w[Community::Topic Community::Post].include?(type)

      type.constantize.find_by(id: report_params[:reportable_id])
    end
  end
end
