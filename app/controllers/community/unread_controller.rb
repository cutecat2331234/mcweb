# frozen_string_literal: true

module Community
  class UnreadController < ApplicationController
    include Community::TopicFilterable
    include Community::TopicListSortable
    include Community::TopicListPreloadable

    before_action :require_login

    def index
      sort = params[:sort].presence || "latest"
      filter = params[:filter].to_s.presence
      section_slug = params[:section].to_s.presence
      scope = Community::ReadState
        .with_unread_for(current_user)
        .includes(topic: TOPIC_LIST_INCLUDES)
        .joins(:topic)

      if filter.present?
        unread_topic_ids = Community::ReadState.with_unread_for(current_user).select(:forum_topic_id)
        filtered_ids = apply_topic_filter(
          Community::Topic.where(id: unread_topic_ids),
          filter: filter,
          user: current_user
        ).select(:id)
        scope = scope.where(forum_topic_id: filtered_ids)
      end

      if section_slug.present?
        section = Community::Section.find_by(slug: section_slug)
        scope = scope.where(forum_topics: { forum_section_id: section.id }) if section
      end

      scope = scope.where.not(forum_topics: { user_id: blocked_user_ids }) if blocked_user_ids.any?
      scope = apply_forum_topic_sort(scope, sort)

      @pagy, read_states = pagy(scope, limit: 20)
      topics = read_states.map(&:topic)
      states_by_topic = read_states.index_by(&:forum_topic_id)

      render inertia: "Community/Unread/Index", props: {
        topics: serialize_topics(topics, read_states: states_by_topic),
        markAllReadUrl: forum_unread_mark_all_read_path,
        markSelectedReadUrl: forum_unread_mark_selected_read_path,
        pagination: pagy_props(@pagy),
        sort: sort,
        filter: filter.to_s,
        section: section_slug.to_s,
        sortOptions: forum_sort_options,
        filterOptions: topic_filter_options,
        sectionOptions: unread_section_options,
        activeFilters: unread_active_filters(sort: sort, filter: filter, section: section_slug)
      }
    end

    def mark_all_read
      result = Community::MarkAllTopicsRead.call(user: current_user)

      if result.success?
        redirect_to forum_unread_path, notice: "全部主题已标记为已读。"
      else
        redirect_to forum_unread_path, alert: service_error_message(result)
      end
    end

    def mark_selected_read
      result = Community::MarkTopicsRead.call(
        user: current_user,
        topic_public_ids: params[:topic_ids]
      )

      if result.success?
        redirect_to forum_unread_path, notice: "已标记 #{result.value[:marked]} 个主题为已读。"
      else
        redirect_to forum_unread_path, alert: result.error || "操作失败"
      end
    end

    private

    def forum_sort_options
      [
        { value: "latest", label: "最新回复" },
        { value: "unread", label: "未读最多" },
        { value: "hot", label: "热门" },
        { value: "replies", label: "回复最多" },
        { value: "newest", label: "最新发布" }
      ]
    end

    def unread_section_options
      unread_topic_ids = Community::ReadState.with_unread_for(current_user).select(:forum_topic_id)
      section_ids = Community::Topic.where(id: unread_topic_ids).distinct.pluck(:forum_section_id)
      sections = Community::Section.where(id: section_ids).order(:name)

      options = [ { value: "", label: "全部分区" } ]
      sections.each do |section|
        options << { value: section.slug, label: section.name }
      end
      options
    end

    def unread_active_filters(sort:, filter:, section:)
      chips = Community::TopicListActiveFilters.call(filter: filter) +
        Community::TopicListSortActiveFilters.call(sort: sort, default: "latest")
      if section.present?
        name = Community::Section.find_by(slug: section)&.name || section
        chips << { param: "section", label: "分区：#{name}", value: section }
      end
      chips
    end
  end
end
