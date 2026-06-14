# frozen_string_literal: true

module Community
  class ReportsController < ApplicationController
    before_action :require_login

    def new
      render inertia: "Community/Reports/New", props: {
        reportableType: params[:reportable_type].to_s,
        reportableId: params[:reportable_id].to_s,
        reasonOptions: Community::Report::REASONS.map { |code, label| { value: code, label: label } }
      }
    end

    def create
      reportable = find_reportable
      return redirect_back fallback_location: root_path, alert: "Content not found." unless reportable

      reason_code = report_params[:reason_code].presence
      detail = report_params[:reason_detail].to_s.strip
      reason_text = if reason_code.present?
                      label = Community::Report::REASONS[reason_code] || reason_code
                      detail.present? ? "#{label}：#{detail}" : label
                    else
                      report_params[:reason]
                    end

      report = Community::Report.create!(
        reporter: current_user,
        reportable: reportable,
        reason: reason_text,
        reason_code: reason_code,
        status: :pending
      )

      Administration::AuditLogger.call(
        actor: current_user,
        action: "community.report_created",
        resource: report
      )

      redirect_back fallback_location: root_path, notice: "Report submitted."
    rescue ActiveRecord::RecordInvalid => e
      render inertia: "Community/Reports/New",
             props: {
               reportableType: report_params[:reportable_type],
               reportableId: report_params[:reportable_id],
               reasonOptions: Community::Report::REASONS.map { |code, label| { value: code, label: label } }
             },
             status: :unprocessable_entity,
             errors: { reason: e.record.errors.full_messages.to_sentence }
    end

    private

    def report_params
      params.require(:report).permit(:reportable_type, :reportable_id, :reason, :reason_code, :reason_detail)
    end

    def find_reportable
      type = report_params[:reportable_type]
      return unless %w[Community::Topic Community::Post].include?(type)

      type.constantize.find_by(id: report_params[:reportable_id])
    end
  end
end
