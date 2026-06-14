# frozen_string_literal: true

module Community
  class WatchedController < ApplicationController
    include Community::TopicListSortable

    before_action :require_login

    def index
      sort = params[:sort].presence || "latest"
      topic_ids = Community::Subscription
        .where(user: current_user, subscribable_type: "Community::Topic")
        .pluck(:subscribable_id)

      topics_scope = Community::Topic
        .where(id: topic_ids, status: :published)
        .includes(:user, :section)
      topics_scope = filter_blocked_topics(topics_scope)
      topics_scope = apply_forum_topic_sort(topics_scope, sort)

      @pagy, topics = pagy(topics_scope, limit: 20)

      read_states = Community::ReadState
        .where(user: current_user, forum_topic_id: topics.map(&:id))
        .index_by(&:forum_topic_id)

      render inertia: "Community/Watched/Index", props: {
        topics: topics.map { |topic| serialize_topic(topic, read_state: read_states[topic.id]) },
        pagination: pagy_props(@pagy),
        sort: sort,
        sortOptions: forum_sort_options
      }
    end

    def tags
      tag_ids = Community::Subscription
        .where(user: current_user, subscribable_type: "Community::Tag")
        .pluck(:subscribable_id)

      tags = Community::Tag.where(id: tag_ids).order(:name)

      render inertia: "Community/Watched/Tags", props: {
        tags: tags.map do |tag|
          {
            name: tag.name,
            slug: tag.slug,
            description: tag.description,
            url: forum_tag_path(tag.slug),
            subscription_url: forum_tag_subscription_path(tag.slug)
          }
        end,
        tagTopicsUrl: forum_watched_tag_topics_path
      }
    end

    def tag_topics
      sort = params[:sort].presence || "latest"
      tag_ids = Community::Subscription
        .where(user: current_user, subscribable_type: "Community::Tag")
        .pluck(:subscribable_id)

      topic_ids = Community::TopicTag.where(forum_tag_id: tag_ids).distinct.pluck(:forum_topic_id)
      topics_scope = Community::Topic
        .where(id: topic_ids, status: :published)
        .includes(:user, :section, :tags)
      topics_scope = filter_blocked_topics(topics_scope)
      topics_scope = apply_forum_topic_sort(topics_scope, sort)
      @pagy, topics = pagy(topics_scope, limit: 20)

      read_states = Community::ReadState
        .where(user: current_user, forum_topic_id: topics.map(&:id))
        .index_by(&:forum_topic_id)

      render inertia: "Community/Watched/TagTopics", props: {
        topics: topics.map { |topic| serialize_topic(topic, read_state: read_states[topic.id]) },
        pagination: pagy_props(@pagy),
        sort: sort,
        sortOptions: forum_sort_options
      }
    end

    private

    def forum_sort_options
      [
        { value: "latest", label: "最新回复" },
        { value: "hot", label: "热门" },
        { value: "replies", label: "回复最多" },
        { value: "newest", label: "最新发布" }
      ]
    end
  end
end
