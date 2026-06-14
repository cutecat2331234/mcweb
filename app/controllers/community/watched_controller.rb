# frozen_string_literal: true

module Community
  class WatchedController < ApplicationController
    before_action :require_login

    def index
      topic_ids = Community::Subscription
        .where(user: current_user, subscribable_type: "Community::Topic")
        .pluck(:subscribable_id)

      topics = Community::Topic
        .where(id: topic_ids, status: :published)
        .includes(:user, :section)
        .order(last_posted_at: :desc)
        .limit(50)
      topics = filter_blocked_topics(topics)

      read_states = Community::ReadState
        .where(user: current_user, forum_topic_id: topics.map(&:id))
        .index_by(&:forum_topic_id)

      render inertia: "Community/Watched/Index", props: {
        topics: topics.map { |topic| serialize_topic(topic, read_state: read_states[topic.id]) }
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
        end
      }
    end
  end
end
