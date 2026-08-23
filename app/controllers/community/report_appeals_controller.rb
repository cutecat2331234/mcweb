# frozen_string_literal: true

module Community
  class ReportAppealsController < ApplicationController
    include PrivateNoStoreResponse

    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

    before_action :require_login
    before_action :set_private_headers
    before_action :set_owned_appeal, only: %i[show submit cancel]

    def index
      @pagy, appeals = pagy(
        :offset,
        Community::ReportAppeal.where(appellant_id: current_user.id)
          .order(state_changed_at: :desc, id: :desc),
        limit: 25
      )
      eligible_reporter_reports = Community::Report
        .where(reporter_id: current_user.id, status: "dismissed")
        .where.not(
          id: Community::ReportAppeal.active
            .where(appellant_id: current_user.id, appellant_role: "reporter")
            .select(:forum_report_id)
        )
        .order(state_changed_at: :desc, id: :desc)
        .limit(25)
      eligible_subject_reports = Community::Report
        .where(affected_user_id: current_user.id, status: "actioned")
        .where.not(
          id: Community::ReportAppeal.active
            .where(appellant_id: current_user.id, appellant_role: "affected_subject")
            .select(:forum_report_id)
        )
        .order(state_changed_at: :desc, id: :desc)
        .limit(25)
      eligible_reports = eligible_reporter_reports.map do |report|
        eligible_report(report, role: "reporter")
      end
      eligible_reports.concat(eligible_subject_reports.map do |report|
        eligible_report(report, role: "affected_subject")
      end)
      eligible_reports.sort_by! { |report| report.fetch(:state_changed_at_sort) }.reverse!
      eligible_reports = eligible_reports.first(25).map { |report| report.except(:state_changed_at_sort) }

      render inertia: "Community/ReportAppeals/Index",
             props: {
               appeals: appeals.map { |appeal| serializer(appeal).summary },
               pagination: pagy_props(@pagy),
               eligible_reports:
             },
             encrypt_history: true
    end

    def show
      render_show
    end

    def submit
      result = Community::SubmitReportAppeal.call(
        appeal: @appeal,
        appellant: current_user,
        reason: appeal_params[:reason],
        attachment_public_ids: appeal_params[:attachment_public_ids],
        idempotency_key: appeal_params[:idempotency_key],
        expected_version: appeal_params[:lock_version]
      )
      return render_show_error(result) if result.failure?

      redirect_to forum_report_appeal_path(@appeal), notice: t("mcweb.flash.report_appeal_submitted")
    end

    def cancel
      result = Community::CancelReportAppeal.call(
        appeal: @appeal,
        appellant: current_user,
        idempotency_key: appeal_params[:idempotency_key],
        expected_version: appeal_params[:lock_version]
      )
      return render_show_error(result) if result.failure?

      redirect_to forum_report_appeals_path, notice: t("mcweb.flash.report_appeal_cancelled")
    end

    private

    def set_owned_appeal
      @appeal = Community::ReportAppeal.where(appellant_id: current_user.id)
        .find_by!(public_id: params[:public_id])
    end

    def render_show(form_errors: nil, status: :ok)
      @appeal.reload
      render inertia: "Community/ReportAppeals/Show",
             props: {
               appeal: serializer(@appeal).detail,
               evidence_upload_url: secure_evidence_attachments_path,
               form_errors:
             },
             status:,
             encrypt_history: true
    end

    def render_show_error(result)
      status = result.code.in?(%w[report_appeal_version_conflict report_appeal_state_conflict]) ? :conflict : :unprocessable_entity
      render_show(form_errors: { base: service_error_message(result) }, status:)
    end

    def serializer(appeal)
      Community::ReportAppealSerializer.new(appeal:, viewer: current_user)
    end

    def eligible_report(report, role:)
      {
        public_id: report.public_id,
        target_label: Community::ReporterReportSerializer.new(report:).safe_target_label,
        state_changed_at: I18n.l(report.state_changed_at, format: :long),
        state_changed_at_sort: report.state_changed_at,
        create_url: appeal_draft_forum_report_path(report),
        appellant_role: role
      }
    end

    def appeal_params
      params.require(:appeal).permit(
        :reason,
        :idempotency_key,
        :lock_version,
        attachment_public_ids: []
      )
    end

    def set_private_headers
      response.set_header("Cache-Control", "private, no-store")
      response.set_header("Pragma", "no-cache")
      response.set_header("X-Robots-Tag", "noindex, nofollow")
    end

    def render_not_found
      set_private_headers
      head :not_found
    end
  end
end
