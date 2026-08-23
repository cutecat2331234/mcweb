# frozen_string_literal: true

module Community
  class ReportAppealPolicy
    def initialize(user)
      @user = user
    end

    def eligible_roles(report)
      return [] unless @user&.session_eligible? && report

      roles = []
      roles << "reporter" if report.dismissed? && report.reporter_id == @user.id
      roles << "affected_subject" if report.actioned? && report.affected_user_id == @user.id
      roles
    end

    def may_create?(report:, role:)
      eligible_roles(report).include?(role.to_s)
    end

    def appellant_visible?(appeal)
      @user&.session_eligible? == true && appeal&.appellant_id == @user.id
    end

    def reviewer?
      return false unless @user&.session_eligible?

      global_report_reviewer? || can_review_private_messages? || moderated_section_ids.any?
    end

    def reviewer_visible?(appeal)
      return false unless appeal && reviewer?
      return false if appeal.draft?
      return false if appeal.submitted_at.nil?
      return false if appeal.appellant_id == @user.id
      return false if appeal.report.reporter_id == @user.id
      return false if appeal.report.affected_user_id == @user.id

      report_visible_to_reviewer?(appeal.report)
    end

    def report_visible_to_reviewer?(report)
      return false unless report && reviewer?
      return false if report.reporter_id == @user.id || report.affected_user_id == @user.id

      if report.reportable_type == "Community::Message"
        can_review_private_messages?
      elsif global_report_reviewer?
        true
      else
        section_id = section_id_for(report)
        section_id.present? && moderated_section_ids.include?(section_id)
      end
    end

    def review_scope
      visible_scope.review_queue
    end

    def visible_scope
      return Community::ReportAppeal.none unless reviewer?

      relation = Community::ReportAppeal.joins(:report).includes(:report, :appellant)
        .where.not(status: "draft")
        .where.not(submitted_at: nil)
        .where.not(appellant_id: @user.id)
        .where.not(forum_reports: { reporter_id: @user.id })
        .where(
          "forum_reports.affected_user_id IS NULL OR forum_reports.affected_user_id <> ?",
          @user.id
        )
      relation.where(forum_report_id: visible_report_scope.select(:id))
    end

    private

    def global_report_reviewer?
      @user&.permission?("forum.topics.lock") == true
    end

    def can_review_private_messages?
      @user&.permission?("forum.conversations.reports.review") == true
    end

    def visible_report_scope
      scope = Community::Report.none
      if global_report_reviewer?
        scope = scope.or(Community::Report.where.not(reportable_type: "Community::Message"))
      end
      if can_review_private_messages?
        scope = scope.or(Community::Report.where(reportable_type: "Community::Message"))
      end

      unless global_report_reviewer?
        section_ids = moderated_section_ids
        return scope unless section_ids.any?

        topic_ids = Community::Topic.with_discarded
          .where(forum_section_id: section_ids)
          .select(:id)
        post_ids = Community::Post.with_discarded
          .where(forum_topic_id: topic_ids)
          .select(:id)
        section_reports = Community::Report
          .where(reportable_type: "Community::Topic", reportable_id: topic_ids)
          .or(
            Community::Report.where(
              reportable_type: "Community::Post",
              reportable_id: post_ids
            )
          )
        scope = scope.or(section_reports)
      end
      scope
    end

    def section_id_for(report)
      case report.reportable_type
      when "Community::Topic"
        Community::Topic.with_discarded.find_by(id: report.reportable_id)&.forum_section_id
      when "Community::Post"
        topic_id = Community::Post.with_discarded.find_by(id: report.reportable_id)&.forum_topic_id
        Community::Topic.with_discarded.find_by(id: topic_id)&.forum_section_id if topic_id
      end
    end

    def moderated_section_ids
      @moderated_section_ids ||= Community::SectionModerator
        .where(user_id: @user&.id)
        .pluck(:forum_section_id)
    end
  end
end
