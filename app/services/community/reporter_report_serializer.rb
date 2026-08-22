# frozen_string_literal: true

module Community
  class ReporterReportSerializer
    SAFE_TARGET_KINDS = {
      "Community::Topic" => "topic",
      "Community::Post" => "post",
      "Community::Message" => "private_message",
      "Community::ProfilePost" => "profile_post",
      "Community::ProfilePostComment" => "profile_post_comment",
      "Commerce::Review" => "review",
      "User" => "user"
    }.freeze

    def initialize(report:, routes: Rails.application.routes.url_helpers)
      @report = report
      @routes = routes
    end

    def summary
      {
        id: @report.id,
        target_label: target_label,
        reason_label: @report.reason_label,
        reason_detail: reason_detail,
        status: @report.status,
        public_outcome_code: @report.public_outcome_code,
        submitted_at: I18n.l(@report.created_at, format: :long),
        state_changed_at: I18n.l(@report.state_changed_at, format: :long),
        lock_version: @report.lock_version,
        detail_url: @routes.forum_report_path(@report),
        can_supplement: @report.pending?,
        can_withdraw: @report.pending?
      }
    end

    def detail
      summary.merge(
        index_url: @routes.forum_reports_path,
        supplement_url: @routes.supplements_forum_report_path(@report),
        withdraw_url: @routes.withdraw_forum_report_path(@report),
        supplements: @report.supplements.order(:created_at, :id).map do |supplement|
          {
            id: supplement.id,
            body: supplement.body,
            created_at: I18n.l(supplement.created_at, format: :long)
          }
        end
      )
    end

    private

    def target_label
      kind = SAFE_TARGET_KINDS.fetch(@report.reportable_type, "content")
      I18n.t("mcweb.forum.reports.targets.#{kind}")
    end

    def reason_detail
      detail = @report.reason.to_s
      return if @report.reason_code.present? && detail == @report.reason_code

      detail.presence
    end
  end
end
