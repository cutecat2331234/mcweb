# frozen_string_literal: true

module Community
  module ModerationWorkbench
    class SyncCases < ApplicationService
      def initialize(now: Time.current)
        @now = now
      end

      def call
        counts = {}
        Community::ModerationCase.transaction do
          counts[:pending_posts] = sync_pending_posts
          counts[:reports] = sync_reports
          counts[:quarantined_attachments] = sync_quarantined_attachments
          counts[:warnings] = sync_warnings
          counts[:mutes] = sync_mutes
          counts[:bans] = sync_bans
        end
        ServiceResult.success(counts)
      rescue ActiveRecord::ActiveRecordError => error
        ServiceResult.failure(error: "moderation_workbench_sync_failed", errors: { base: [ error.message ] })
      end

      private

      def sync_pending_posts
        seen = []
        Community::Post.pending_review.includes(:user, topic: :section).find_each do |post|
          seen << post.id
          opening = post.floor_number == 1
          upsert_case(
            source: post,
            source_kind: opening ? "pending_topic" : "pending_post",
            section: post.topic.section,
            target_user: post.user,
            title: opening ? post.topic.title : "Reply awaiting review",
            summary: "Submitted by #{post.user.username} in #{post.topic.section.name}",
            priority: "normal",
            risk_level: "medium",
            metadata: {
              author_username: post.user.username,
              topic_public_id: post.topic.public_id,
              floor_number: post.floor_number
            }
          )
        end
        mark_stale("Community::Post", seen)
        seen.size
      end

      def sync_reports
        seen = []
        Community::Report.pending_review.includes(:reporter, :reviewer, :reportable).find_each do |report|
          seen << report.id
          section = section_for(report.reportable)
          target_user = user_for(report.reportable)
          spam = report.reason_code == "spam"
          upsert_case(
            source: report,
            source_kind: spam ? "spam_hit" : "report",
            section: section,
            target_user: target_user,
            title: report_title(report),
            summary: "Reported by #{report.reporter.username}",
            priority: spam ? "high" : "normal",
            risk_level: spam ? "high" : "medium",
            metadata: {
              reporter_username: report.reporter.username,
              reportable_type: report.reportable_type,
              reason_code: report.reason_code
            }.compact
          )
        end
        mark_stale("Community::Report", seen)
        seen.size
      end

      def sync_quarantined_attachments
        seen = []
        Community::Upload
          .where(manual_review_status: %w[none revoked])
          .where(
            "scan_status = 'infected' OR (scan_status = 'error' AND quarantined_at IS NOT NULL)"
          )
          .includes(:user, :post_attachment, post: { topic: :section })
          .find_each do |upload|
            seen << upload.id
            upsert_case(
              source: upload,
              source_kind: "quarantined_attachment",
              section: upload.post&.topic&.section || upload.post_attachment&.post&.topic&.section,
              target_user: upload.user,
              title: I18n.t(
                "mcweb.user_copy.moderation_quarantined_attachment",
                id: upload.public_id
              ),
              summary: I18n.t(
                "mcweb.user_copy.moderation_quarantined_attachment_summary",
                username: upload.user.username
              ),
              priority: "critical",
              risk_level: "critical",
              metadata: {
                upload_public_id: upload.public_id,
                owner_username: upload.user.username,
                upload_kind: upload.kind
              }
            )
          end
        mark_stale("Community::Upload", seen)
        seen.size
      end

      def sync_warnings
        seen = []
        Community::UserWarning.active.includes(:user, :issuer).find_each do |warning|
          seen << warning.id
          high_risk = warning.points >= 5
          upsert_case(
            source: warning,
            source_kind: "user_risk",
            target_user: warning.user,
            title: I18n.t(
              "mcweb.user_copy.moderation_active_warning",
              username: warning.user.username
            ),
            summary: I18n.t(
              "mcweb.user_copy.moderation_active_warning_summary",
              points: warning.points,
              issuer: warning.issuer.username
            ),
            priority: high_risk ? "high" : "normal",
            risk_level: high_risk ? "high" : "medium",
            metadata: {
              event_type: "warning",
              points: warning.points,
              expires_at: warning.expires_at&.iso8601
            }.compact
          )
        end
        mark_stale("Community::UserWarning", seen)
        seen.size
      end

      def sync_mutes
        seen = []
        Community::Mute.active.includes(:user, :created_by, :section).find_each do |mute|
          seen << mute.id
          upsert_case(
            source: mute,
            source_kind: "user_risk",
            section: mute.section,
            target_user: mute.user,
            title: I18n.t(
              "mcweb.user_copy.moderation_active_mute",
              username: mute.user.username
            ),
            summary:
              if mute.section
                I18n.t("mcweb.user_copy.moderation_section_mute", section: mute.section.name)
              else
                I18n.t("mcweb.user_copy.moderation_sitewide_mute")
              end,
            priority: "high",
            risk_level: "high",
            metadata: {
              event_type: "mute",
              expires_at: mute.expires_at&.iso8601
            }.compact
          )
        end
        mark_stale("Community::Mute", seen)
        seen.size
      end

      def sync_bans
        seen = []
        User.where(status: "banned")
          .where("ban_expires_at IS NULL OR ban_expires_at > ?", @now)
          .find_each do |user|
            seen << user.id
            upsert_case(
              source: user,
              source_kind: "user_risk",
              target_user: user,
              title: I18n.t(
                "mcweb.user_copy.moderation_active_account_ban",
                username: user.username
              ),
              summary: I18n.t("mcweb.user_copy.moderation_account_suspended"),
              priority: "critical",
              risk_level: "critical",
              metadata: {
                event_type: "ban",
                expires_at: user.ban_expires_at&.iso8601
              }.compact
            )
          end
        mark_stale("User", seen)
        seen.size
      end

      def upsert_case(source:, source_kind:, title:, summary:, priority:, risk_level:,
                      metadata:, section: nil, target_user: nil)
        moderation_case = Community::ModerationCase.find_or_initialize_by(
          source_type: source.class.base_class.name,
          source_id: source.id
        )
        moderation_case.status = "open" if moderation_case.new_record? || moderation_case.status_stale?
        moderation_case.assign_attributes(
          source: source,
          source_kind: source_kind,
          section: section,
          target_user: target_user,
          title: title.to_s.squish.first(255),
          summary: summary.to_s.squish.first(500),
          priority: priority,
          risk_level: risk_level,
          metadata: metadata,
          source_updated_at: source.updated_at || source.created_at
        )
        moderation_case.save! if moderation_case.changed?
        moderation_case
      rescue ActiveRecord::RecordNotUnique
        retry
      end

      def mark_stale(source_type, seen_ids)
        scope = Community::ModerationCase
          .active_queue
          .where(source_type: source_type)
        scope = scope.where.not(source_id: seen_ids) if seen_ids.any?
        scope.update_all(
          status: "stale",
          resolved_at: @now,
          updated_at: @now,
          lock_version: Arel.sql("lock_version + 1")
        )
      end

      def section_for(reportable)
        case reportable
        when Community::Topic then reportable.section
        when Community::Post then reportable.topic&.section
        end
      end

      def user_for(reportable)
        case reportable
        when User then reportable
        when Community::Topic, Community::Post, Community::Message then reportable.user
        when Commerce::Review then reportable.user
        when Community::ProfilePost then reportable.user
        end
      end

      def report_title(report)
        case report.reportable
        when Community::Topic
          "Reported topic: #{report.reportable.title}"
        when Community::Post
          "Reported reply in #{report.reportable.topic.title}"
        when User
          "Reported user: #{report.reportable.username}"
        when Community::Message
          I18n.t("mcweb.user_copy.moderation_reported_private_message")
        else
          "Reported #{report.reportable_type.to_s.demodulize.underscore.humanize.downcase}"
        end
      end
    end
  end
end
