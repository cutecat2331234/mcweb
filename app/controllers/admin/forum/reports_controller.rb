# frozen_string_literal: true

module Admin
  module Forum
    class ReportsController < BaseController
      include PrivateNoStoreResponse

      before_action :set_report_privacy_headers
      before_action :require_report_access
      before_action :set_report, only: %i[show update claim resolve_target reveal_evidence]
      before_action :authorize_report, only: %i[show update claim resolve_target reveal_evidence]

      def index
        # Reviewables-style prioritization: surface targets with the most pending
        # flags first (distinct reporters per reportable), then most recent.
        scope = authorized_reports_scope.pending_review
        flag_counts = scope.group(:reportable_type, :reportable_id).distinct.count(:reporter_id)
        reports = scope.order(created_at: :desc).to_a.sort_by do |report|
          [ -flag_counts.fetch([ report.reportable_type, report.reportable_id ], 1), -report.created_at.to_i ]
        end

        render inertia: "Admin/Generic/Index", props: {
          title: forum_t("reports.title"),
          columns: [
            admin_column(:reason, forum_t("reports.col_reason"), link: true),
            admin_column(:flags, forum_t("reports.col_flags")),
            admin_column(:reporter, forum_t("reports.col_reporter")),
            admin_column(:status, forum_t("reports.col_status")),
            admin_column(:time, forum_t("reports.col_time"))
          ],
          rows: reports.map do |report|
            admin_row(
              reason: report_reason_summary(report),
              flags: flag_counts.fetch([ report.reportable_type, report.reportable_id ], 1).to_s,
              reporter: report.reporter&.username,
              status: report.status,
              time: l(report.created_at, format: :short),
              url: admin_forum_report_path(report)
            )
          end
        }, encrypt_history: true
      end

      def show
        response.headers["Cache-Control"] = "private, no-store" if private_message_report?
        render_report
      end

      def reveal_evidence
        evidence = @report.evidence
        return head :not_found unless evidence

        response.headers["Cache-Control"] = "private, no-store"
        response.headers["Pragma"] = "no-cache"
        Administration::AuditLogger.call(
          actor: current_user,
          action: "admin.forum_report_evidence_revealed",
          resource: @report,
          metadata: {
            subject_type: evidence.subject_type,
            subject_id: evidence.subject_id,
            subject_revision: evidence.subject_revision,
            content_digest: evidence.content_digest
          }
        )
        render_report(reveal_evidence: true)
      end

      def render_report(reveal_evidence: false)
        fields = [
          { label: forum_t("reports.field_type"), value: @report.reason_label || forum_na },
          { label: forum_t("reports.field_reason"), value: report_reason_detail(@report) },
          { label: forum_t("reports.field_reporter"), value: @report.reporter&.username || forum_na },
          { label: forum_t("reports.field_reviewer"), value: @report.reviewer&.username || forum_na },
          { label: forum_t("reports.field_status"), value: @report.status },
          { label: forum_t("reports.field_target"), value: reportable_label },
          { label: forum_t("reports.field_time"), value: l(@report.created_at, format: :long) }
        ]
        if reveal_evidence && @report.evidence
          fields.concat([
            { label: forum_t("reports.field_evidence_revision"), value: @report.evidence.subject_revision.to_s },
            { label: forum_t("reports.field_evidence_digest"), value: @report.evidence.content_digest },
            { label: forum_t("reports.field_evidence_body"), value: @report.evidence.snapshot.fetch("body", forum_na) }
          ])
        end

        render inertia: "Admin/Generic/Show", props: {
          title: forum_t("reports.show_title"),
          fields: fields,
          backUrl: admin_forum_reports_path,
          actions: report_actions + evidence_actions(reveal_evidence: reveal_evidence) + reportable_actions
        }, encrypt_history: true
      end

      def update
        status = report_params[:status].to_s
        unless Community::Report::STAFF_FINAL_STATUSES.include?(status)
          return redirect_to admin_forum_report_path(@report), alert: service_error_message(
            ServiceResult.failure(error: "report_state_invalid")
          )
        end

        result = Community::DecideReport.call(
          report: @report,
          reviewer: current_user,
          internal_note: report_params[:review_note],
          desired_status: status,
          expected_version: report_params[:lock_version],
          idempotency_key: report_params[:idempotency_key]
        )
        unless result.success?
          return redirect_to admin_forum_report_path(@report), alert: service_error_message(result)
        end

        redirect_to admin_forum_report_path(@report), notice: t("mcweb.flash.report_resolved")
      end

      # Claim a report for review without resolving it (assign reviewer).
      def claim
        @report.update!(reviewer: current_user)
        redirect_to admin_forum_report_path(@report), notice: t("mcweb.flash.report_claimed")
      end

      # Resolve ALL pending reports for the same reported target at once.
      def resolve_target
        status = report_params[:status].to_s
        unless Community::Report::STAFF_FINAL_STATUSES.include?(status)
          return redirect_to admin_forum_report_path(@report), alert: service_error_message(
            ServiceResult.failure(error: "report_state_invalid")
          )
        end

        result = Community::DecideReports.call(
          scope: authorized_reports_scope,
          reportable: @report.reportable,
          reviewer: current_user,
          desired_status: status,
          internal_note: report_params[:review_note],
          idempotency_key: report_params[:idempotency_key]
        )
        unless result.success?
          return redirect_to admin_forum_report_path(@report), alert: service_error_message(result)
        end

        count = result.value.fetch(:count)

        unless result.value.fetch(:replayed)
          Administration::AuditLogger.call(
            actor: current_user,
            action: "admin.forum_reports_bulk_resolved",
            resource: @report.reportable,
            metadata: {
              count: count,
              status: status,
              disposition: report_disposition(@report, status: status)
            }
          )
        end
        redirect_to admin_forum_reports_path, notice: t("mcweb.flash.reports_bulk_resolved", count: count)
      end

      private

      def require_report_access
        return if can_review_regular_reports? || can_review_private_messages?

        redirect_to root_path, alert: t("mcweb.flash.permission_denied")
      end

      def authorize_report
        allowed = private_message_report? ? can_review_private_messages? : can_review_regular_reports?
        return if allowed

        head :not_found
      end

      def authorized_reports_scope
        if can_review_regular_reports? && can_review_private_messages?
          ::Community::Report.all
        elsif can_review_private_messages?
          ::Community::Report.where(reportable_type: "Community::Message")
        elsif can_review_regular_reports?
          ::Community::Report.where.not(reportable_type: "Community::Message")
        else
          ::Community::Report.none
        end
      end

      def can_review_regular_reports?
        current_user&.permission?("forum.topics.lock") == true
      end

      def can_review_private_messages?
        current_user&.permission?("forum.conversations.reports.review") == true
      end

      def private_message_report?
        @report&.reportable_type == "Community::Message"
      end

      def set_report
        @report = ::Community::Report.find(params[:id])
      end

      def report_params
        params.fetch(:report, {}).permit(
          :status,
          :review_note,
          :lock_version,
          :idempotency_key
        )
      end

      def report_actions
        return [] unless @report.pending?

        [
          {
            label: forum_t(report_action_label_key),
            href: admin_forum_report_path(@report),
            method: "patch",
            confirm: forum_t("reports.confirm_actioned"),
            data: report_decision_data("actioned")
          },
          {
            label: forum_t("reports.action_reviewed"),
            href: admin_forum_report_path(@report),
            method: "patch",
            variant: "outline",
            confirm: forum_t("reports.confirm_reviewed"),
            data: report_decision_data("reviewed")
          },
          {
            label: forum_t("reports.action_dismiss"),
            href: admin_forum_report_path(@report),
            method: "patch",
            variant: "outline",
            confirm: forum_t("reports.confirm_dismissed"),
            data: report_decision_data("dismissed")
          },
          {
            label: forum_t("reports.action_claim"),
            href: claim_admin_forum_report_path(@report),
            method: "patch",
            variant: "outline"
          },
          {
            label: forum_t(report_action_label_key(bulk: true)),
            href: resolve_target_admin_forum_report_path(@report),
            method: "patch",
            variant: "outline",
            confirm: forum_t("reports.confirm_bulk_actioned"),
            data: report_decision_data("actioned", include_version: false)
          },
          {
            label: forum_t("reports.action_resolve_target_dismiss"),
            href: resolve_target_admin_forum_report_path(@report),
            method: "patch",
            variant: "outline",
            confirm: forum_t("reports.confirm_bulk_dismissed"),
            data: report_decision_data("dismissed", include_version: false)
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
        when ::Community::ProfilePost
          forum_t("reports.target_profile_post", username: @report.reportable.profile_user.username)
        when ::Community::ProfilePostComment
          forum_t("reports.target_profile_comment", username: profile_wall_username(@report.reportable))
        when ::Community::Message
          forum_t("reports.target_private_message", id: @report.reportable_id)
        when ::User
          forum_t("reports.target_user", username: @report.reportable.username)
        else
          "#{@report.reportable_type} ##{@report.reportable_id}"
        end
      end

      def report_decision_data(status, include_version: true)
        payload = {
          status: status,
          idempotency_key: SecureRandom.uuid
        }
        payload[:lock_version] = @report.lock_version if include_version
        { report: payload }
      end

      def set_report_privacy_headers
        response.set_header("Cache-Control", "private, no-store")
        response.set_header("Pragma", "no-cache")
        response.set_header("X-Robots-Tag", "noindex, nofollow")
      end

      def report_reason_summary(report)
        label = report.reason_label.presence
        detail = report_reason_detail(report, fallback: nil)
        return [ label, detail&.truncate(40) ].compact.join(" — ") if label

        report.reason.to_s.truncate(60)
      end

      def report_reason_detail(report, fallback: forum_na)
        detail = report.reason.to_s
        detail = nil if report.reason_code.present? && detail == report.reason_code
        detail.presence || fallback
      end

      def reportable_actions
        case @report.reportable
        when ::Community::Topic
          [ { label: forum_t("reports.action_view_topic"), href: forum_topic_path(@report.reportable) } ]
        when ::Community::Post
          [ { label: forum_t("reports.action_view_post"), href: "#{forum_topic_path(@report.reportable.topic)}#post-#{@report.reportable.id}" } ]
        when ::Commerce::Review
          [ { label: forum_t("reports.action_view_product"), href: store_product_path(@report.reportable.product) } ]
        when ::Community::ProfilePost
          [ { label: forum_t("reports.action_view_profile_post"), href: forum_user_path(@report.reportable.profile_user.username) } ]
        when ::Community::ProfilePostComment
          username = profile_wall_username(@report.reportable, fallback: nil)
          username ? [ { label: forum_t("reports.action_view_profile_post"), href: forum_user_path(username) } ] : []
        when ::User
          [ { label: forum_t("reports.action_view_user"), href: forum_user_path(@report.reportable.username) } ]
        else
          []
        end
      end

      def evidence_actions(reveal_evidence:)
        return [] unless private_message_report?
        return [] if reveal_evidence || @report.evidence.blank?

        [
          {
            label: forum_t("reports.action_reveal_evidence"),
            href: reveal_evidence_admin_forum_report_path(@report),
            method: "post",
            variant: "outline"
          }
        ]
      end

      def report_disposition(report, status:)
        normalized = status.to_s
        return normalized unless normalized == "actioned"

        return "upheld_private_message_evidence_retained" if report.reportable_type == "Community::Message"
        return "actioned_and_hidden" if hideable_reportable?(report)

        "upheld_without_content_mutation"
      end

      def report_action_label_key(bulk: false)
        if private_message_report?
          bulk ? "reports.action_uphold_all_private_messages" : "reports.action_uphold_private_message"
        elsif hideable_reportable?(@report)
          bulk ? "reports.action_resolve_target_action" : "reports.action_agree"
        else
          bulk ? "reports.action_uphold_all" : "reports.action_uphold"
        end
      end

      def hideable_reportable?(report)
        reportable = report.reportable
        [
          Community::Topic,
          Community::Post,
          Community::ProfilePost
        ].any? { |type| reportable.is_a?(type) }
      end

      def profile_wall_username(comment, fallback: forum_na)
        Community::ProfilePost.with_discarded
          .find_by(id: comment.profile_post_id)
          &.profile_user
          &.username || fallback
      end
    end
  end
end
