# frozen_string_literal: true

module Community
  class TagsController < ApplicationController
    before_action :require_login, only: %i[toggle_subscription]

    def index
      tags = Community::Tag.usable_by(current_user)
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
      tag = Community::Tag.usable_by(current_user).find_by!(slug: params[:slug])
      sort = params[:sort].to_s.presence || "activity"
      topic_ids = tag.topics.where(status: :published).pluck(:id)
      scope = Community::Topic.where(id: topic_ids).sorted(sort).includes(:user)
      scope = filter_blocked_topics(scope)
      @pagy, topics = pagy(scope, limit: 20)

      read_states = if logged_in?
                      Community::ReadState.where(user: current_user, forum_topic_id: topics.map(&:id)).index_by(&:forum_topic_id)
                    else
                      {}
                    end

      watching = logged_in? && Community::Subscription.exists?(user: current_user, subscribable: tag)

      render inertia: "Community/Tags/Show", props: {
        tag: {
          name: tag.name,
          slug: tag.slug,
          description: tag.description,
          rss_url: forum_tag_rss_path(tag.slug),
          watching: watching,
          subscription_url: forum_tag_subscription_path(tag.slug)
        },
        topics: topics.map { |topic| serialize_topic(topic, read_state: read_states[topic.id]) },
        pagination: pagy_props(@pagy),
        sort: sort,
        loggedIn: logged_in?
      }
    end

    def toggle_subscription
      tag = Community::Tag.usable_by(current_user).find_by!(slug: params[:slug])
      result = Community::ToggleTagSubscription.call(user: current_user, tag: tag)

      if result.success?
        redirect_to forum_tag_path(tag.slug),
                    notice: result.value[:watching] ? "已关注此标签。" : "已取消关注此标签。"
      else
        redirect_to forum_tag_path(tag.slug), alert: service_error_message(result)
      end
    end
  end
end
