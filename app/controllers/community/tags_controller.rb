# frozen_string_literal: true

module Community
  class TagsController < ApplicationController
    include Community::TopicListPreloadable

    before_action :require_login, only: %i[toggle_subscription]

    def index
      usable_ids = Community::Tag.usable_by(current_user).pluck(:id).to_set
      tags = Community::Tag.usable_by(current_user)
        .left_joins(:topic_tags)
        .group(:id)
        .select("forum_tags.*, COUNT(forum_topic_tags.id) AS topics_count")
        .order("topics_count DESC")
        .limit(100)

      grouped_tag_ids = Set.new
      tag_groups = Community::TagGroup.includes(:tags).ordered.filter_map do |group|
        group_tags = group.tags.select { |tag| usable_ids.include?(tag.id) }
        next if group_tags.empty?

        group_tags.each { |tag| grouped_tag_ids.add(tag.id) }
        {
          name: group.name,
          slug: group.slug,
          color_hex: group.color_hex,
          tags: group_tags.map do |tag|
            count = tags.find { |t| t.id == tag.id }&.topics_count.to_i
            {
              name: tag.name,
              slug: tag.slug,
              topics_count: count,
              color_hex: tag.color_hex,
              url: forum_tag_path(tag.slug)
            }
          end.sort_by { |t| -t[:topics_count] }
        }
      end

      ungrouped = tags.reject { |tag| grouped_tag_ids.include?(tag.id) }.map do |tag|
        {
          name: tag.name,
          slug: tag.slug,
          topics_count: tag.topics_count.to_i,
          color_hex: tag.color_hex,
          url: forum_tag_path(tag.slug)
        }
      end

      render inertia: "Community/Tags/Index", props: {
        tagGroups: tag_groups,
        ungroupedTags: ungrouped
      }
    end

    def show
      tag = Community::Tag.resolve_by_slug(params[:slug])
      return head :not_found unless tag

      tag = Community::Tag.usable_by(current_user).find_by!(id: tag.id)
      sort = params[:sort].to_s.presence || "activity"
      topic_ids = tag.topics.published_listed.pluck(:id)
      scope = preload_topics(Community::Topic.where(id: topic_ids).sorted(sort))
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
          color_hex: tag.color_hex,
          rss_url: forum_tag_rss_path(tag.slug),
          watching: watching,
          subscription_url: forum_tag_subscription_path(tag.slug)
        },
        topics: serialize_topics(topics, read_states: read_states),
        pagination: pagy_props(@pagy),
        sort: sort,
        loggedIn: logged_in?
      }
    end

    def toggle_subscription
      tag = Community::Tag.usable_by(current_user).find_by!(slug: params[:slug])
      result = Community::ToggleTagSubscription.call(user: current_user, tag: tag)

      if result.success?
        notice = if result.value[:watching]
                   case result.value[:notification_level]
                   when "tracking" then "已切换为跟踪此标签（仅站内通知）。"
                   when "normal" then "已切换为普通（不接收标签新主题通知）。"
                   else "已关注此标签（即时通知）。"
                   end
        else
                   "已取消关注此标签。"
        end
        redirect_to forum_tag_path(tag.slug), notice: notice
      else
        redirect_to forum_tag_path(tag.slug), alert: service_error_message(result)
      end
    end
  end
end
