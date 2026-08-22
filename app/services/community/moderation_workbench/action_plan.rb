# frozen_string_literal: true

module Community
  module ModerationWorkbench
    class ActionPlan
      ACTIONS = %w[
        approve reject resolve_case dismiss_case resolve_report dismiss_report
        delete_content move_topic release_attachment delete_attachment
        warn_user mute_user ban_user
      ].freeze
      CLOSING_ACTIONS = %w[
        approve reject resolve_report dismiss_report delete_content
        release_attachment delete_attachment
      ].freeze
      USER_ACTIONS = %w[warn_user mute_user ban_user].freeze

      def initialize(actor:, action:, moderation_cases:, attributes: {})
        @actor = actor
        @action = action.to_s
        @moderation_cases = moderation_cases.sort_by(&:id)
        @attributes = stringify_keys(attributes)
        @policy = Policy.new(actor)
      end

      attr_reader :action, :attributes, :moderation_cases

      def valid_action?
        ACTIONS.include?(action)
      end

      def preview
        seen_targets = {}
        moderation_cases.map do |moderation_case|
          error = eligibility_error(moderation_case)
          target_key = error ? nil : mutation_target_key(moderation_case)
          shared_target = target_key && seen_targets.key?(target_key)
          seen_targets[target_key] = true if target_key
          {
            case_id: moderation_case.id,
            title: moderation_case.title,
            source_kind: moderation_case.source_kind,
            eligible: error.nil?,
            message: error ||
              (shared_target ? "shared_target_will_be_actioned_once" : impact_for(moderation_case)),
            before: {
              status: moderation_case.status,
              assignee_id: moderation_case.assignee_id,
              source_state: source_state(moderation_case)
            },
            after: predicted_after(moderation_case, error).merge(
              shared_target: shared_target || false
            )
          }
        end
      end

      def state
        moderation_cases.map do |moderation_case|
          source = safe_source(moderation_case)
          {
            case_id: moderation_case.id,
            lock_version: moderation_case.lock_version,
            status: moderation_case.status,
            source_type: moderation_case.source_type,
            source_id: moderation_case.source_id,
            source_updated_at: moderation_case.source_updated_at&.iso8601(6),
            live_source: source_state(moderation_case),
            target_user: USER_ACTIONS.include?(action) ? user_state(target_user(source)) : nil
          }
        end
      end

      def targets
        moderation_cases.map do |moderation_case|
          {
            case_id: moderation_case.id,
            source_kind: moderation_case.source_kind,
            source_type: moderation_case.source_type,
            source_id: moderation_case.source_id
          }
        end
      end

      def any_eligible?
        preview.any? { |item| item[:eligible] }
      end

      def eligibility_error(moderation_case)
        return "moderation_case_forbidden" unless @policy.visible?(moderation_case)
        return "moderation_case_closed" unless moderation_case.status.in?(Community::ModerationCase::ACTIVE_STATUSES)
        return "moderation_action_not_available" unless @policy.available_actions(moderation_case).include?(action)
        return nil if action.in?(%w[resolve_case dismiss_case])

        source = safe_source(moderation_case)
        return "moderation_source_stale" unless source

        case action
        when "approve", "reject"
          return "post_not_pending_approval" unless source.is_a?(Community::Post) &&
            source.status == "pending_approval"
        when "resolve_report", "dismiss_report"
          return "report_not_pending" unless source.is_a?(Community::Report) && source.status == "pending"
        when "delete_content"
          return "moderation_content_not_supported" unless content_target(source)
        when "move_topic"
          topic = topic_target(source)
          section = destination_section
          return "moderation_destination_required" unless section
          return "moderation_topic_not_supported" unless topic
          return "topic_already_in_section" if topic.forum_section_id == section.id
          unless Community::SectionModeration.can_move_topic?(
            user: @actor,
            topic: topic,
            to_section: section
          )
            return "moderation_move_forbidden"
          end
        when "release_attachment"
          return "attachment_not_quarantined" unless source.is_a?(Community::Upload) &&
            source.scan_quarantined?
        when "delete_attachment"
          return "attachment_already_cleaned" unless source.is_a?(Community::Upload) &&
            !source.status_cleaned?
        when "warn_user"
          return "moderation_warning_attributes_invalid" unless warning_attributes_valid?
          return "moderation_target_user_missing" unless target_user(source)
        when "mute_user"
          return "moderation_mute_attributes_invalid" unless duration_days.between?(1, 3_650)
          return "moderation_target_user_missing" unless target_user(source)
        when "ban_user"
          return "moderation_ban_attributes_invalid" unless duration_days.between?(0, 3_650)
          return "moderation_target_user_missing" unless target_user(source)
        end

        nil
      end

      def target_user(source)
        case source
        when User then source
        when Community::Post, Community::Upload, Community::UserWarning, Community::Mute
          source.user
        when Community::Report
          case source.reportable
          when User then source.reportable
          when Community::Post, Community::Topic, Community::Message then source.reportable.user
          end
        end
      end

      def topic_target(source)
        case source
        when Community::Post then source.topic
        when Community::Report
          case source.reportable
          when Community::Topic then source.reportable
          when Community::Post then source.reportable.topic
          end
        end
      end

      def content_target(source)
        case source
        when Community::Post then source
        when Community::Report
          source.reportable if source.reportable.is_a?(Community::Post) ||
            source.reportable.is_a?(Community::Topic)
        end
      end

      def mutation_target_key(moderation_case)
        source = safe_source(moderation_case)
        return unless source

        target =
          case action
          when "move_topic"
            topic_target(source)
          when "delete_content"
            content = content_target(source)
            content.is_a?(Community::Post) && content.floor_number == 1 ? content.topic : content
          when "resolve_report", "dismiss_report"
            source.reportable if source.is_a?(Community::Report)
          when *USER_ACTIONS
            target_user(source)
          end
        return unless target

        [ target.class.base_class.name, target.id ]
      end

      def destination_section
        id = Integer(attributes["section_id"], exception: false)
        @destination_section ||= Community::Section.find_by(id: id) if id&.positive?
      end

      def warning_points
        Integer(attributes["points"], exception: false) || 1
      end

      def warning_expire_days
        Integer(attributes["expire_days"], exception: false)
      end

      def duration_days
        Integer(attributes["duration_days"], exception: false) || 0
      end

      private

      def safe_source(moderation_case)
        moderation_case.source
      rescue ActiveRecord::RecordNotFound
        nil
      end

      def source_state(moderation_case)
        source = safe_source(moderation_case)
        return { missing: true } unless source

        base = {
          updated_at: source.updated_at&.iso8601(6)
        }
        case source
        when Community::Post
          base.merge(
            status: source.status,
            deleted_at: source.deleted_at&.iso8601(6),
            topic_id: source.forum_topic_id,
            topic_status: source.topic.status,
            topic_updated_at: source.topic.updated_at&.iso8601(6)
          )
        when Community::Report
          base.merge(
            status: source.status,
            lock_version: source.lock_version,
            reviewer_id: source.reviewer_id,
            reviewed_at: source.reviewed_at&.iso8601(6),
            reportable_type: source.reportable_type,
            reportable_id: source.reportable_id,
            reportable: reportable_state(source.reportable)
          )
        when Community::Upload
          base.merge(
            status: source.status,
            scan_status: source.scan_status,
            scan_result_code: source.scan_result_code,
            manual_review_status: source.manual_review_status,
            manual_review_version: source.manual_review_version
          )
        when Community::UserWarning
          base.merge(expires_at: source.expires_at&.iso8601(6), points: source.points)
        when Community::Mute
          base.merge(expires_at: source.expires_at&.iso8601(6), section_id: source.forum_section_id)
        when User
          base.merge(status: source.status, ban_expires_at: source.ban_expires_at&.iso8601(6))
        else
          base
        end
      end

      def predicted_after(moderation_case, error)
        return { status: moderation_case.status, skipped: true } if error

        case action
        when "dismiss_case", "dismiss_report"
          { status: "dismissed" }
        when "resolve_case"
          { status: "resolved" }
        when *CLOSING_ACTIONS
          { status: "actioned", action: action }
        else
          { status: moderation_case.status, action: action, remains_open: true }
        end
      end

      def reportable_state(reportable)
        base = {
          type: reportable&.class&.base_class&.name,
          id: reportable&.id,
          updated_at: reportable&.updated_at&.iso8601(6)
        }
        case reportable
        when Community::Post
          base.merge(
            topic_id: reportable.forum_topic_id,
            topic_section_id: reportable.topic.forum_section_id,
            topic_status: reportable.topic.status,
            topic_updated_at: reportable.topic.updated_at&.iso8601(6)
          )
        when Community::Topic
          base.merge(
            section_id: reportable.forum_section_id,
            status: reportable.status,
            deleted_at: reportable.deleted_at&.iso8601(6)
          )
        when User
          base.merge(
            status: reportable.status,
            ban_expires_at: reportable.ban_expires_at&.iso8601(6)
          )
        else
          base
        end
      end

      def user_state(user)
        return { missing: true } unless user

        {
          id: user.id,
          updated_at: user.updated_at&.iso8601(6),
          status: user.status,
          account_type: user.account_type,
          deleted_at: user.deleted_at&.iso8601(6),
          banned_at: user.banned_at&.iso8601(6),
          ban_expires_at: user.ban_expires_at&.iso8601(6)
        }
      end

      def impact_for(moderation_case)
        {
          "approve" => "publish_pending_content",
          "reject" => "hide_pending_content",
          "resolve_case" => "close_workbench_case",
          "dismiss_case" => "dismiss_workbench_case",
          "resolve_report" => report_resolution_impact(moderation_case),
          "dismiss_report" => "dismiss_report_and_restore_target_when_safe",
          "delete_content" => "soft_delete_content",
          "move_topic" => "move_topic_to_section_#{destination_section&.id}",
          "release_attachment" => "release_quarantined_attachment",
          "delete_attachment" => "schedule_attachment_cleanup",
          "warn_user" => "issue_#{warning_points}_warning_points",
          "mute_user" => "mute_user_for_#{duration_days}_days",
          "ban_user" => duration_days.zero? ? "ban_user_permanently" : "ban_user_for_#{duration_days}_days"
        }.fetch(action, "moderate_case_#{moderation_case.id}")
      end

      def private_message_report?(moderation_case)
        source = safe_source(moderation_case)
        source.is_a?(Community::Report) && source.reportable_type == "Community::Message"
      end

      def report_resolution_impact(moderation_case)
        return "uphold_private_message_report_and_retain_evidence" if private_message_report?(moderation_case)

        source = safe_source(moderation_case)
        hideable = source.is_a?(Community::Report) && [
          Community::Topic,
          Community::Post,
          Community::ProfilePost
        ].any? { |type| source.reportable.is_a?(type) }
        return "uphold_report_without_content_mutation" unless hideable

        "agree_with_report_and_hide_target"
      end

      def warning_attributes_valid?
        warning_points.between?(1, 10) &&
          (warning_expire_days.nil? || warning_expire_days.between?(0, 3_650))
      end

      def stringify_keys(value)
        raw = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value.to_h
        raw.deep_stringify_keys
      rescue NoMethodError
        {}
      end
    end
  end
end
