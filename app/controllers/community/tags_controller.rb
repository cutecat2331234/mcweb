# frozen_string_literal: true

module Community
  class TagsController < ApplicationController
    def show
      tag = Community::Tag.find_by!(slug: params[:slug])
      topic_ids = tag.topics.where(status: :published).pluck(:id)
      @pagy, topics = pagy(
        Community::Topic.where(id: topic_ids).pinned_first.includes(:user),
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
        pagination: pagy_props(@pagy)
      }
    end
  end
end
