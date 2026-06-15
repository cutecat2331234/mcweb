# frozen_string_literal: true

module Community
  class UnreadController < ApplicationController
    include Community::TopicListSortable
    include Community::TopicListPreloadable

    before_action :require_login

    def index
      sort = params[:sort].presence || "latest"
      scope = Community::ReadState
        .with_unread_for(current_user)
        .includes(topic: TOPIC_LIST_INCLUDES)
        .joins(:topic)

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
        sortOptions: forum_sort_options
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
  end
end
