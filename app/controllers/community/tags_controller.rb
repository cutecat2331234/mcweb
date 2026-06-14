# frozen_string_literal: true

module Community
  class TagsController < ApplicationController
    def index
      tags = Community::Tag
        .left_joins(:topic_tags)
        .group(:id)
        .select("forum_tags.*, COUNT(forum_topic_tags.id) AS topics_count")
        .order("topics_count DESC")
        .limit(100)

      render inertia: "Community/Tags/Index", props: {
        tags: tags.map do |tag|
          {
            name: tag.name,
            slug: tag.slug,
            topics_count: tag.topics_count.to_i,
            url: forum_tag_path(tag.slug)
          }
        end
      }
    end

    def show
      tag = Community::Tag.find_by!(slug: params[:slug])
      sort = params[:sort].to_s.presence || "activity"
      topic_ids = tag.topics.where(status: :published).pluck(:id)
      @pagy, topics = pagy(
        Community::Topic.where(id: topic_ids).sorted(sort).includes(:user),
        limit: 20
      )

      read_states = if logged_in?
                      Community::ReadState.where(user: current_user, forum_topic_id: topics.map(&:id)).index_by(&:forum_topic_id)
                    else
                      {}
                    end

      render inertia: "Community/Tags/Show", props: {
        tag: { name: tag.name, slug: tag.slug },
        topics: topics.map { |topic| serialize_topic(topic, read_state: read_states[topic.id]) },
        pagination: pagy_props(@pagy),
        sort: sort
      }
    end
  end
end
