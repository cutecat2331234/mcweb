# frozen_string_literal: true

module Community
  class ReportsController < ApplicationController
    before_action :require_login

    def new
      render inertia: "Community/Reports/New", props: {
        reportableType: params[:reportable_type].to_s,
        reportableId: params[:reportable_id].to_s,
        reasonOptions: Community::Report.reason_options.map { |code, label| { value: code, label: label } }
      }
    end

    def create
      result = Community::CreateReport.call(
        reporter: current_user,
        reportable_type: report_params[:reportable_type],
        reportable_id: report_params[:reportable_id],
        reason: report_params[:reason],
        reason_code: report_params[:reason_code],
        reason_detail: report_params[:reason_detail],
        ip_address: request.remote_ip
      )

      if result.rate_limited?
        apply_retry_after_header(result)
        return redirect_back fallback_location: root_path, alert: t("mcweb.flash.report_rate_limited")
      end

      if result.code == "report_target_unavailable"
        return redirect_back fallback_location: root_path, alert: t("mcweb.flash.content_not_found")
      end

      return render_failure(result) if result.failure?

      redirect_back fallback_location: root_path, notice: t("mcweb.flash.report_submitted")
    end

    private

    def render_failure(result)
      render inertia: "Community/Reports/New",
             props: {
               reportableType: report_params[:reportable_type],
               reportableId: report_params[:reportable_id],
               reasonOptions: Community::Report.reason_options.map { |code, label| { value: code, label: label } },
               form_errors: { "report.reason" => result.error.presence || result.errors.values.flatten.join("；") }
             },
             status: :unprocessable_entity
    end

    def report_params
      params.require(:report).permit(:reportable_type, :reportable_id, :reason, :reason_code, :reason_detail)
    end
  end
end
