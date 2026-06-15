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
      tag_slugs = unread_tag_slugs
      tag_match = unread_tag_match
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

      if tag_slugs.any?
        scope = apply_unread_tag_filters(scope, tag_slugs, match: tag_match)
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
        tags: tag_slugs.join(","),
        tagMatch: tag_match,
        tagMatchOptions: unread_tag_match_options,
        sortOptions: forum_sort_options,
        filterOptions: topic_filter_options,
        sectionOptions: unread_section_options,
        tagOptions: unread_tag_options,
        activeFilters: unread_active_filters(sort: sort, filter: filter, section: section_slug, tag_slugs: tag_slugs, tag_match: tag_match)
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

    def unread_tag_options
      unread_topic_ids = Community::ReadState.with_unread_for(current_user).select(:forum_topic_id)
      tag_ids = Community::TopicTag.where(forum_topic_id: unread_topic_ids).distinct.pluck(:forum_tag_id)
      tags = Community::Tag.where(id: tag_ids).order(:name)

      options = [ { value: "", label: "全部标签" } ]
      tags.each do |tag|
        options << { value: tag.slug, label: tag.name }
      end
      options
    end

    def unread_tag_ids_for(tag_slug)
      canonical = Community::Tag.find_by(slug: tag_slug)
      return [] unless canonical

      [ canonical.id ] + Community::Tag.where(canonical_tag_id: canonical.id).pluck(:id)
    end

    def unread_tag_slugs
      raw = params[:tags].presence || params[:tag].presence
      return [] unless raw

      raw.to_s.split(",").map(&:strip).reject(&:blank?).uniq
    end

    def unread_tag_match
      match = params[:tag_match].to_s.presence || "all"
      %w[all any].include?(match) ? match : "all"
    end

    def unread_tag_match_options
      [
        { value: "all", label: "全部标签" },
        { value: "any", label: "任意标签" }
      ]
    end

    def apply_unread_tag_filters(scope, tag_slugs, match:)
      unread_topic_ids = Community::ReadState.with_unread_for(current_user).select(:forum_topic_id)

      if match == "any"
        all_tag_ids = tag_slugs.flat_map { |slug| unread_tag_ids_for(slug) }.uniq
        return scope.none if all_tag_ids.empty?

        topic_ids = Community::TopicTag
          .where(forum_tag_id: all_tag_ids, forum_topic_id: unread_topic_ids)
          .distinct
          .pluck(:forum_topic_id)
        return scope.none if topic_ids.empty?

        return scope.where(forum_topic_id: topic_ids)
      end

      filtered_topic_ids = nil

      tag_slugs.each do |slug|
        tag_ids = unread_tag_ids_for(slug)
        return scope.none if tag_ids.empty?

        topic_ids = Community::TopicTag
          .where(forum_tag_id: tag_ids, forum_topic_id: unread_topic_ids)
          .distinct
          .pluck(:forum_topic_id)

        filtered_topic_ids = filtered_topic_ids.nil? ? topic_ids : (filtered_topic_ids & topic_ids)
        return scope.none if filtered_topic_ids.empty?
      end

      scope.where(forum_topic_id: filtered_topic_ids)
    end

    def unread_active_filters(sort:, filter:, section:, tag_slugs:, tag_match:)
      chips = Community::TopicListActiveFilters.call(filter: filter) +
        Community::TopicListSortActiveFilters.call(sort: sort, default: "latest")
      if section.present?
        name = Community::Section.find_by(slug: section)&.name || section
        chips << { param: "section", label: "分区：#{name}", value: section }
      end
      if tag_slugs.many? && tag_match == "any"
        chips << { param: "tag_match", label: "标签匹配：任意", value: "any" }
      elsif tag_slugs.many?
        chips << { param: "tag_match", label: "标签匹配：全部", value: "all" }
      end
      tag_slugs.each do |slug|
        name = Community::Tag.find_by(slug: slug)&.name || slug
        chips << { param: "tags", label: "标签：#{name}", value: slug }
      end
      chips
    end
  end
end
