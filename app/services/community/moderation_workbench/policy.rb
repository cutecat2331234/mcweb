# frozen_string_literal: true

module Community
  module ModerationWorkbench
    class Policy
      CONTENT_KINDS = %w[pending_topic pending_post].freeze
      REPORT_KINDS = %w[report spam_hit].freeze
      ATTACHMENT_READ_PERMISSION = "forum.attachments.security.read"
      ATTACHMENT_MANAGE_PERMISSION = "forum.attachments.security.manage"
      ATTACHMENT_RELEASE_PERMISSION = "forum.attachments.security.release"
      PRIVATE_MESSAGE_REPORT_PERMISSION = "forum.conversations.reports.review"

      def initialize(actor)
        @actor = actor
      end

      attr_reader :actor

      def accessible?
        Community::SectionModeration.staff_for_any_section?(actor) ||
          actor&.permission?(ATTACHMENT_READ_PERMISSION) ||
          can_review_private_message_reports? ||
          actor&.permission?("forum.users.warn") ||
          actor&.permission?("forum.users.mute") ||
          actor&.account_owner?
      end

      def visible_scope(relation = Community::ModerationCase.all)
        visible = relation.none

        moderated_ids = moderated_section_ids
        if global_moderator?
          visible = visible.or(relation.where(source_kind: CONTENT_KINDS))
          visible = visible.or(
            relation
              .where(source_kind: REPORT_KINDS)
              .where.not(
                source_type: "Community::Report",
                source_id: private_message_report_ids
              )
          )
        elsif moderated_ids.any?
          visible = visible.or(content_scope(relation, moderated_ids))
          visible = visible.or(report_scope(relation, moderated_ids))
        end

        if can_review_private_message_reports?
          visible = visible.or(
            relation.where(
              source_kind: REPORT_KINDS,
              source_type: "Community::Report",
              source_id: private_message_report_ids
            )
          )
        end

        if attachment_reader?
          visible = visible.or(relation.where(source_kind: "quarantined_attachment"))
        end
        visible = visible.or(relation.where(source_kind: "user_risk")) if actor&.account_owner?
        if actor&.permission?("forum.users.warn") && !actor&.account_owner?
          visible = visible.or(
            relation.where(
              source_kind: "user_risk",
              source_type: "Community::UserWarning"
            )
          )
        end
        if actor&.permission?("forum.users.mute") && !actor&.account_owner?
          visible = visible.or(
            relation.where(
              source_kind: "user_risk",
              source_type: "Community::Mute"
            )
          )
        end

        return visible unless actor

        participant_report_ids = Community::Report
          .where("reporter_id = :user_id OR affected_user_id = :user_id", user_id: actor.id)
          .select(:id)
        visible.where.not(
          source_type: "Community::Report",
          source_id: participant_report_ids
        )
      end

      def visible?(moderation_case)
        return false unless moderation_case

        case moderation_case.source_kind
        when *CONTENT_KINDS
          source = safe_source(moderation_case)
          source.is_a?(Community::Post) &&
            can_moderate_section?(section_for_post(source))
        when *REPORT_KINDS
          source = safe_source(moderation_case)
          return false if source.is_a?(Community::Report) && report_participant?(source)
          return can_review_private_message_reports? if private_message_report?(moderation_case)
          return true if global_moderator?

          source.is_a?(Community::Report) &&
            can_moderate_section?(section_for_reportable(reportable_for(source)))
        when "quarantined_attachment"
          attachment_reader?
        when "user_risk"
          case moderation_case.source_type
          when "Community::UserWarning"
            actor&.permission?("forum.users.warn") || actor&.account_owner?
          when "Community::Mute"
            actor&.permission?("forum.users.mute") || actor&.account_owner?
          when "User"
            actor&.account_owner?
          else
            false
          end
        else
          false
        end
      end

      # Evidence is deliberately not implied by ordinary forum read access.
      # Each source family requires its existing moderation/security permission.
      def evidence_visible?(moderation_case)
        return false unless visible?(moderation_case)
        # Private-message evidence is available only through the dedicated,
        # explicitly audited reveal action on the report page.
        return false if private_message_report?(moderation_case)

        case safe_source(moderation_case)
        when Community::UserWarning
          actor&.permission?("forum.users.warn") || actor&.account_owner?
        when Community::Mute
          actor&.permission?("forum.users.mute") || actor&.account_owner?
        when User
          actor&.account_owner?
        else
          true
        end
      end

      def attachment_reader?
        actor&.permission?(ATTACHMENT_READ_PERMISSION)
      end

      def attachment_manager?
        actor&.permission?(ATTACHMENT_MANAGE_PERMISSION)
      end

      def attachment_releaser?
        actor&.permission?(ATTACHMENT_RELEASE_PERMISSION)
      end

      def can_review_private_message_reports?
        actor&.permission?(PRIVATE_MESSAGE_REPORT_PERMISSION) == true
      end

      def global_moderator?
        Community::SectionModeration.global_moderator?(actor)
      end

      def can_moderate_section?(section)
        Community::SectionModeration.can_moderate?(user: actor, section: section)
      end

      def can_move_topic?(topic)
        topic.present? &&
          Community::SectionModeration.can_move_topic?(user: actor, topic: topic)
      end

      def can_warn?(user)
        actor&.permission?("forum.users.warn") && user.present? && actor.id != user.id
      end

      def can_mute?(user)
        actor&.permission?("forum.users.mute") && user.present? && actor.id != user.id
      end

      def can_ban?(user)
        actor&.account_owner? && user.present? && actor.id != user.id
      end

      def can_assign?(moderation_case, user)
        return false unless can_manage_case?(moderation_case)
        return true if user.nil?
        return false unless user.status == "active"

        assignee_policy = self.class.new(user)
        assignee_policy.accessible? && assignee_policy.can_manage_case?(moderation_case)
      end

      def assignable_staff(moderation_case)
        assignable_candidates(moderation_case).where(status: "active").order(:username).select do |user|
          can_assign?(moderation_case, user)
        end
      end

      def can_manage_case?(moderation_case)
        return false unless visible?(moderation_case)

        case moderation_case.source_kind
        when "quarantined_attachment"
          attachment_manager? || attachment_releaser?
        else
          true
        end
      end

      def available_actions(moderation_case)
        return [] unless can_manage_case?(moderation_case)
        return [] unless moderation_case.status.in?(Community::ModerationCase::ACTIVE_STATUSES)

        source = safe_source(moderation_case)
        return %w[resolve_case dismiss_case] unless source

        actions = %w[resolve_case dismiss_case assign note]
        actions << "claim" if moderation_case.assignee_id.nil?
        return actions if source.is_a?(Community::Post) && source.deleted_at.present?

        case source
        when Community::Post
          actions.prepend("approve", "reject") if source.status == "pending_approval"
          actions << "delete_content" if can_moderate_section?(source.topic&.section)
          actions << "move_topic" if can_move_topic?(source.topic)
          append_user_actions(actions, source.user)
        when Community::Report
          if source.status == "pending"
            actions.prepend("resolve_report", "dismiss_report")
            append_reportable_actions(actions, source.reportable)
          end
        when Community::Upload
          if attachment_releaser? && attachment_release_candidate?(source)
            actions.prepend("release_attachment")
          end
          actions << "delete_attachment" if attachment_manager? && !source.status_cleaned?
          append_user_actions(actions, source.user)
        when Community::UserWarning, Community::Mute
          append_user_actions(actions, source.user)
        when User
          append_user_actions(actions, source)
        end

        actions.uniq
      end

      private

      def assignable_candidates(moderation_case)
        ids = User.where(account_type: "owner").pluck(:id)
        permission_keys = []

        case moderation_case.source_kind
        when *CONTENT_KINDS, *REPORT_KINDS
          if private_message_report?(moderation_case)
            permission_keys << PRIVATE_MESSAGE_REPORT_PERMISSION
          else
            permission_keys << "forum.topics.lock"
          end
          if moderation_case.forum_section_id && !private_message_report?(moderation_case)
            ids.concat(
              Community::SectionModerator
                .where(forum_section_id: moderation_case.forum_section_id)
                .pluck(:user_id)
            )
          end
        when "quarantined_attachment"
          permission_keys.concat([ ATTACHMENT_MANAGE_PERMISSION, ATTACHMENT_RELEASE_PERMISSION ])
        when "user_risk"
          permission_keys << "forum.users.warn" if moderation_case.source_type == "Community::UserWarning"
          permission_keys << "forum.users.mute" if moderation_case.source_type == "Community::Mute"
        end

        ids.concat(user_ids_with_any_permission(permission_keys))
        User.where(id: ids.uniq)
      end

      # Permission candidates include direct roles and global identity groups.
      # This avoids scanning every account while preserving the same effective
      # permission sources used by User#permission?.
      def user_ids_with_any_permission(permission_keys)
        keys = Array(permission_keys).map(&:to_s).uniq
        return [] if keys.empty?

        role_user_ids = User.joins(roles: :permissions)
          .where(permissions: { key: keys })
          .distinct
          .pluck(:id)
        group_ids = Community::UserGroup.all.filter_map do |group|
          group.id if (group.permission_keys & keys).any?
        end
        group_user_ids = Community::GroupMembership
          .where(community_user_group_id: group_ids)
          .distinct
          .pluck(:user_id)

        role_user_ids + group_user_ids
      end

      def moderated_section_ids
        @moderated_section_ids ||= Community::SectionModeration
          .moderated_sections_for(actor)
          .pluck(:id)
      end

      def content_scope(relation, section_ids)
        topic_ids = Community::Topic.with_discarded
          .where(forum_section_id: section_ids)
          .select(:id)
        post_ids = Community::Post.with_discarded
          .where(forum_topic_id: topic_ids)
          .select(:id)
        relation.where(
          source_kind: CONTENT_KINDS,
          source_type: "Community::Post",
          source_id: post_ids
        )
      end

      def report_scope(relation, section_ids)
        topic_ids = Community::Topic.with_discarded
          .where(forum_section_id: section_ids)
          .select(:id)
        post_ids = Community::Post.with_discarded
          .where(forum_topic_id: topic_ids)
          .select(:id)
        report_ids = Community::Report
          .where(reportable_type: "Community::Post", reportable_id: post_ids)
          .or(
            Community::Report.where(
              reportable_type: "Community::Topic",
              reportable_id: topic_ids
            )
          )
          .select(:id)
        relation.where(
          source_kind: REPORT_KINDS,
          source_type: "Community::Report",
          source_id: report_ids
        )
      end

      def private_message_report_ids
        Community::Report.where(reportable_type: "Community::Message").select(:id)
      end

      def private_message_report?(moderation_case)
        source = safe_source(moderation_case)
        source.is_a?(Community::Report) && source.reportable_type == "Community::Message"
      end

      def report_participant?(report)
        actor && (report.reporter_id == actor.id || report.affected_user_id == actor.id)
      end

      def section_for_reportable(reportable)
        case reportable
        when Community::Topic then reportable.section
        when Community::Post then section_for_post(reportable)
        end
      end

      def section_for_post(post)
        Community::Topic.with_discarded
          .find_by(id: post.forum_topic_id)
          &.section
      end

      def safe_source(moderation_case)
        if moderation_case.source_type == "Community::Post"
          Community::Post.with_discarded.find_by(id: moderation_case.source_id)
        else
          moderation_case.source
        end
      rescue ActiveRecord::RecordNotFound
        nil
      end

      def reportable_for(report)
        case report.reportable_type
        when "Community::Post"
          Community::Post.with_discarded.find_by(id: report.reportable_id)
        when "Community::Topic"
          Community::Topic.with_discarded.find_by(id: report.reportable_id)
        else
          report.reportable
        end
      end

      def append_reportable_actions(actions, reportable)
        topic =
          case reportable
          when Community::Topic then reportable
          when Community::Post then reportable.topic
          end
        if topic && can_moderate_section?(topic.section)
          actions << "delete_content"
          actions << "move_topic" if can_move_topic?(topic)
        end

        target_user =
          case reportable
          when User then reportable
          when Community::Topic, Community::Post, Community::Message then reportable.user
          end
        append_user_actions(actions, target_user)
      end

      def append_user_actions(actions, user)
        actions << "warn_user" if can_warn?(user)
        actions << "mute_user" if can_mute?(user)
        actions << "ban_user" if can_ban?(user)
      end

      def attachment_release_candidate?(upload)
        upload.kind_post_attachment? &&
          upload.user_id != actor.id &&
          !upload.status_cleaned? &&
          upload.scan_status_infected? &&
          upload.manual_review_status_none? &&
          upload.scan_result_code.in?(
            Community::ReleaseQuarantinedUpload::RELEASABLE_RESULT_CODES
          )
      end
    end
  end
end
