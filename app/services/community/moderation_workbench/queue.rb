# frozen_string_literal: true

module Community
  module ModerationWorkbench
    class Queue
      FILTER_KEYS = %i[
        source_kind status priority risk_level section_id assignee_id from to
      ].freeze

      def initialize(actor:, filters: {})
        @actor = actor
        @policy = Policy.new(actor)
        @filters = normalize_filters(filters)
      end

      attr_reader :filters, :policy

      def relation
        scope = policy.visible_scope(
          Community::ModerationCase.includes(:section, :assignee, :target_user)
        )
        scope = default_status_scope(scope)
        scope = enum_filter(scope, :source_kind, Community::ModerationCase::SOURCE_KINDS)
        scope = enum_filter(scope, :priority, Community::ModerationCase::PRIORITIES)
        scope = enum_filter(scope, :risk_level, Community::ModerationCase::RISK_LEVELS)
        scope = section_filter(scope)
        scope = assignee_filter(scope)
        scope = time_filter(scope, :from, ">=")
        scope = time_filter(scope, :to, "<=")
        scope.recent_first
      end

      def serialize(moderation_case)
        {
          id: moderation_case.id,
          source_kind: moderation_case.source_kind,
          status: moderation_case.status,
          priority: moderation_case.priority,
          risk_level: moderation_case.risk_level,
          title: moderation_case.title,
          summary: moderation_case.summary,
          section: moderation_case.section && {
            id: moderation_case.section.id,
            name: moderation_case.section.name,
            slug: moderation_case.section.slug
          },
          target_user: moderation_case.target_user && {
            id: moderation_case.target_user.id,
            username: moderation_case.target_user.username
          },
          assignee: moderation_case.assignee && {
            id: moderation_case.assignee.id,
            username: moderation_case.assignee.username,
            name: moderation_case.assignee.username
          },
          claimed_at: moderation_case.claimed_at&.iso8601,
          updated_at: moderation_case.updated_at.iso8601,
          source_updated_at: moderation_case.source_updated_at.iso8601,
          lock_version: moderation_case.lock_version,
          available_actions: policy.available_actions(moderation_case)
        }
      end

      def filter_options
        visible_sections = Community::Section.where(
          id: policy.visible_scope
            .where.not(forum_section_id: nil)
            .select(:forum_section_id)
        )
        moderation_sections = Community::SectionModeration.moderated_sections_for(@actor)
        available_sections = visible_sections.or(
          Community::Section.where(id: moderation_sections.select(:id))
        ).order(:name)
        visible_staff = User.where(
          id: policy.visible_scope
            .where.not(assignee_id: nil)
            .select(:assignee_id)
        ).order(:username)

        {
          source_kinds: Community::ModerationCase::SOURCE_KINDS,
          statuses: [ "active", *Community::ModerationCase::STATUSES ],
          priorities: Community::ModerationCase::PRIORITIES,
          risk_levels: Community::ModerationCase::RISK_LEVELS,
          sections: available_sections.map { |section| { id: section.id, name: section.name } },
          move_sections: moderation_sections.order(:name).map do |section|
            { id: section.id, name: section.name }
          end,
          staff: visible_staff.map do |user|
            { id: user.id, value: user.id, username: user.username, name: user.username }
          end
        }
      end

      private

      def normalize_filters(values)
        raw = values.respond_to?(:to_unsafe_h) ? values.to_unsafe_h : values.to_h
        normalized = FILTER_KEYS.index_with do |key|
          raw[key].presence || raw[key.to_s].presence
        end
        normalized[:status] ||= "active"
        normalized
      end

      def default_status_scope(scope)
        value = filters[:status].to_s
        return scope if value == "all"
        return scope.where(status: value) if Community::ModerationCase::STATUSES.include?(value)

        scope.active_queue
      end

      def enum_filter(scope, key, allowed)
        value = filters[key].to_s
        allowed.include?(value) ? scope.where(key => value) : scope
      end

      def section_filter(scope)
        id = positive_integer(filters[:section_id])
        id ? scope.where(forum_section_id: id) : scope
      end

      def assignee_filter(scope)
        value = filters[:assignee_id].to_s
        return scope.where(assignee_id: nil) if value == "unassigned"
        return scope.where(assignee_id: @actor.id) if value == "me"

        id = positive_integer(value)
        id ? scope.where(assignee_id: id) : scope
      end

      def time_filter(scope, key, operator)
        value = filters[key]
        return scope if value.blank?

        time = Time.zone.parse(value.to_s)
        key == :to ? scope.where("source_updated_at #{operator} ?", time.end_of_day) :
          scope.where("source_updated_at #{operator} ?", time.beginning_of_day)
      rescue ArgumentError, TypeError
        scope
      end

      def positive_integer(value)
        number = Integer(value, exception: false)
        number if number&.positive?
      end
    end
  end
end
