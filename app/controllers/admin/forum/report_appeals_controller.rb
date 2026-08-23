# frozen_string_literal: true

module Admin
  module Forum
    class ReportAppealsController < BaseController
      include PrivateNoStoreResponse

      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

      before_action :set_private_headers
      before_action :require_access
      before_action :set_appeal, only: %i[show update seal_evidence]

      def index
        @pagy, appeals = pagy(
          :offset,
          filtered_scope.order(state_changed_at: :asc, id: :asc),
          limit: 25
        )
        render inertia: "Admin/Forum/ReportAppeals/Index",
               props: {
                 appeals: appeals.map { |appeal| serializer(appeal).summary },
                 pagination: pagy_props(@pagy),
                 filters: { status: params[:status].to_s.presence }
               },
               encrypt_history: true
      end

      def show
        render inertia: "Admin/Forum/ReportAppeals/Show",
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
        return redirect_to(admin_forum_report_appeal_path(@appeal), alert: service_error_message(result)) if result.failure?

        redirect_to admin_forum_report_appeal_path(@appeal), notice: t("mcweb.flash.report_appeal_decided")
      end

      def seal_evidence
        result = Community::SealReportAppealEvidence.call(
          appeal: @appeal,
          reviewer: current_user,
          attachment_public_ids: evidence_params[:attachment_public_ids]
        )
        if result.failure?
          return redirect_to admin_forum_report_appeal_path(@appeal), alert: service_error_message(result)
        end

        redirect_to admin_forum_report_appeal_path(@appeal), notice: t("mcweb.flash.report_evidence_added")
      end

      private

      def require_access
        return if appeal_policy.reviewer?

        head :not_found
      end

      def filtered_scope
        status = params[:status].to_s
        if status.in?(Community::ReportAppeal::STATUSES - [ "draft" ])
          return appeal_policy.visible_scope.where(status:)
        end

        appeal_policy.review_scope
      end

      def set_appeal
        @appeal = appeal_policy.visible_scope.find_by!(public_id: params[:public_id])
      end

      def serializer(appeal)
        Community::ReportAppealReviewSerializer.new(
          appeal:,
          viewer: current_user,
          decision_url: admin_forum_report_appeal_path(appeal),
          detail_url: admin_forum_report_appeal_path(appeal),
          evidence_url: evidence_admin_forum_report_appeal_path(appeal)
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

      def set_private_headers
        response.set_header("Cache-Control", "private, no-store")
        response.set_header("Pragma", "no-cache")
        response.set_header("X-Robots-Tag", "noindex, nofollow")
      end

      def render_not_found
        head :not_found
      end
    end
  end
end
