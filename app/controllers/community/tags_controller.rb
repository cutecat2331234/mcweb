# frozen_string_literal: true

module Community
  class TagsController < ApplicationController
    include Community::TopicListPreloadable
    include Community::SectionVisibility

    include Community::SubscriptionNoticeable

    before_action :require_login, only: %i[toggle_subscription update_subscription suggest]

    def suggest
      q = params[:q].to_s.strip
      return render(json: { tags: [] }) if q.blank?

      needle = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
      tags = Community::Tag.usable_by(current_user)
        .where("name ILIKE ? OR slug ILIKE ?", needle, needle)
        .order(:name)
        .limit(8)
        .map { |tag| { name: tag.name, slug: tag.slug } }
      render json: { tags: tags }
    end

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
      topic_ids = tag.topics.published_listed.merge(Community::Topic.accessible_by(current_user)).pluck(:id)
      scope = preload_topics(Community::Topic.where(id: topic_ids).sorted(sort))
      scope = filter_blocked_topics(scope)
      @pagy, topics = pagy(:offset, scope, limit: 20)

      read_states = if logged_in?
                      Community::ReadState.where(user: current_user, forum_topic_id: topics.map(&:id)).index_by(&:forum_topic_id)
      else
                      {}
      end

      subscription = logged_in? ? Community::Subscription.find_by(user: current_user, subscribable: tag) : nil

      render inertia: "Community/Tags/Show", props: {
        tag: {
          name: tag.name,
          slug: tag.slug,
          description: tag.description,
          color_hex: tag.color_hex,
          rss_url: forum_tag_rss_path(tag.slug),
          watching: subscription.present?,
          notification_level: subscription&.notification_level,
          subscription_url: forum_tag_subscription_level_path(tag.slug)
        },
        topics: serialize_topics(topics, read_states: read_states),
        pagination: pagy_props(@pagy),
        sort: sort,
        loggedIn: logged_in?,
        subscriptionLevels: Community::SubscriptionLevelOptions.for(:tag)
      }
    end

    def toggle_subscription
      tag = Community::Tag.usable_by(current_user).find_by!(slug: params[:slug])
      result = Community::ToggleTagSubscription.call(user: current_user, tag: tag)

      if result.success?
        notice = subscription_notice(result.value[:watching], result.value[:notification_level], context: :tag)
        redirect_to forum_tag_path(tag.slug, params.permit(:sort).compact_blank), notice: notice
      else
        redirect_to forum_tag_path(tag.slug, params.permit(:sort).compact_blank), alert: service_error_message(result)
      end
    end

    def update_subscription
      tag = Community::Tag.usable_by(current_user).find_by!(slug: params[:slug])
      result = Community::SetSubscriptionLevel.call(
        user: current_user,
        subscribable: tag,
        level: params[:level]
      )

      if result.success?
        notice = subscription_notice(result.value[:watching], result.value[:notification_level], context: :tag)
        redirect_after_subscription_update(fallback_location: forum_tag_path(tag.slug), notice: notice)
      else
        redirect_after_subscription_update(fallback_location: forum_tag_path(tag.slug), alert: result.error || t("mcweb.flash.subscription_update_failed"))
      end
    end
  end
end
