# frozen_string_literal: true

module Staff
  class ReportAppealsController < BaseController
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

    before_action :require_appeal_access
    before_action :set_appeal, only: %i[show update seal_evidence]

    def index
      @pagy, appeals = pagy(
        :offset,
        filtered_scope.order(state_changed_at: :asc, id: :asc),
        limit: 25
      )
      render inertia: "Staff/ReportAppeals/Index",
             props: {
               appeals: appeals.map { |appeal| serializer(appeal).summary },
               pagination: pagy_props(@pagy),
               filters: { status: params[:status].to_s.presence }
             },
             encrypt_history: true
    end

    def show
      render inertia: "Staff/ReportAppeals/Show",
             props: { appeal: serializer(@appeal).detail },
             encrypt_history: true
    end

    def update
      result = Community::DecideReportAppeal.call(
        appeal: @appeal,
        reviewer: current_user,
        decision: decision_params[:decision],
        internal_note: decision_params[:internal_note],
        idempotency_key: decision_params[:idempotency_key],
        expected_version: decision_params[:lock_version]
      )
      return redirect_to(staff_report_appeal_path(@appeal), alert: service_error_message(result)) if result.failure?

      redirect_to staff_report_appeal_path(@appeal), notice: t("mcweb.flash.report_appeal_decided")
    end

    def seal_evidence
      result = Community::SealReportAppealEvidence.call(
        appeal: @appeal,
        reviewer: current_user,
        attachment_public_ids: evidence_params[:attachment_public_ids]
      )
      return redirect_to(staff_report_appeal_path(@appeal), alert: service_error_message(result)) if result.failure?

      redirect_to staff_report_appeal_path(@appeal), notice: t("mcweb.flash.report_evidence_added")
    end

    private

    def require_appeal_access
      head :not_found unless appeal_policy.reviewer?
    end

    def filtered_scope
      status = params[:status].to_s
      return appeal_policy.visible_scope.where(status:) if status.in?(Community::ReportAppeal::STATUSES - [ "draft" ])

      appeal_policy.review_scope
    end

    def set_appeal
      @appeal = appeal_policy.visible_scope.find_by!(public_id: params[:public_id])
    end

    def serializer(appeal)
      Community::ReportAppealReviewSerializer.new(
        appeal:,
        viewer: current_user,
        decision_url: staff_report_appeal_path(appeal),
        detail_url: staff_report_appeal_path(appeal),
        evidence_url: evidence_staff_report_appeal_path(appeal)
      )
    end

    def appeal_policy
      @appeal_policy ||= Community::ReportAppealPolicy.new(current_user)
    end

    def decision_params
      params.require(:appeal).permit(:decision, :internal_note, :idempotency_key, :lock_version)
    end

    def evidence_params
      params.require(:evidence).permit(attachment_public_ids: [])
    end

    def render_not_found
      head :not_found
    end
  end
end
