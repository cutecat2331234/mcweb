# frozen_string_literal: true

module Community
  class ReportsController < ApplicationController
    include PrivateNoStoreResponse

    rescue_from ActiveRecord::RecordNotFound, with: :render_report_not_found

    before_action :set_report_privacy_headers
    before_action :require_login
    before_action :set_owned_report, only: %i[show supplements withdraw]

    def index
      @pagy, reports = pagy(
        :offset,
        Community::Report.where(reporter_id: current_user.id).order(created_at: :desc, id: :desc),
        limit: 25
      )
      render inertia: "Community/Reports/Index",
             props: {
               reports: reports.map { |report| reporter_serializer(report).summary },
               pagination: pagy_props(@pagy)
             },
             encrypt_history: true
    end

    def show
      render_report_show
    end

    def new
      render inertia: "Community/Reports/New",
             props: new_report_props(
               reportable_type: params[:reportable_type],
               reportable_id: params[:reportable_id]
             ),
             encrypt_history: true
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

      redirect_to forum_report_path(result.value), notice: t("mcweb.flash.report_submitted")
    end

    def supplements
      result = Community::AddReportSupplement.call(
        report: @report,
        reporter: current_user,
        body: supplement_params[:body],
        idempotency_key: supplement_params[:idempotency_key],
        expected_version: supplement_params[:lock_version]
      )
      unless result.success?
        return render_report_show(
          form_errors: { "supplement.body" => service_error_message(result) },
          status: report_mutation_status(result)
        )
      end

      redirect_to forum_report_path(@report), notice: t("mcweb.flash.report_supplement_added")
    end

    def withdraw
      result = Community::WithdrawReport.call(
        report: @report,
        reporter: current_user,
        desired_state: withdrawal_params[:desired_state],
        idempotency_key: withdrawal_params[:idempotency_key],
        expected_version: withdrawal_params[:lock_version]
      )
      unless result.success?
        return render_report_show(
          form_errors: { base: service_error_message(result) },
          status: report_mutation_status(result)
        )
      end

      redirect_to forum_report_path(@report), notice: t("mcweb.flash.report_withdrawn")
    end

    private

    def render_failure(result)
      render inertia: "Community/Reports/New",
             props: new_report_props(
               reportable_type: report_params[:reportable_type],
               reportable_id: report_params[:reportable_id],
               form_errors: { "report.reason" => service_error_message(result) }
             ),
             status: :unprocessable_entity,
             encrypt_history: true
    end

    def render_report_show(form_errors: nil, status: :ok)
      @report.reload if @report.persisted?
      render inertia: "Community/Reports/Show",
             props: {
               report: reporter_serializer(@report).detail,
               form_errors: form_errors
             },
             status: status,
             encrypt_history: true
    end

    def new_report_props(reportable_type:, reportable_id:, form_errors: nil)
      {
        reportableType: reportable_type.to_s,
        reportableId: reportable_id.to_s,
        reasonOptions: Community::Report.reason_options.map do |code, label|
          { value: code, label: label }
        end,
        formAction: forum_reports_path,
        indexUrl: forum_reports_path,
        form_errors: form_errors
      }
    end

    def reporter_serializer(report)
      Community::ReporterReportSerializer.new(report: report)
    end

    def set_owned_report
      @report = Community::Report.where(reporter_id: current_user.id).find(params[:id])
    end

    def set_report_privacy_headers
      response.set_header("Cache-Control", "private, no-store")
      response.set_header("Pragma", "no-cache")
      response.set_header("X-Robots-Tag", "noindex, nofollow")
    end

    def render_report_not_found
      set_report_privacy_headers
      head :not_found
    end

    def report_mutation_status(result)
      return :conflict if result.code.in?(%w[report_version_conflict report_state_conflict])

      :unprocessable_entity
    end

    def report_params
      params.require(:report).permit(:reportable_type, :reportable_id, :reason, :reason_code, :reason_detail)
    end

    def supplement_params
      params.require(:supplement).permit(:body, :idempotency_key, :lock_version)
    end

    def withdrawal_params
      params.require(:report).permit(:desired_state, :idempotency_key, :lock_version)
    end
  end
end
