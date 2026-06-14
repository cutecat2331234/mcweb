# frozen_string_literal: true

module Community
  class SectionsController < ApplicationController
    include Community::TopicFilterable

    def index
      @pagy, sections = pagy(Community::Section.roots.ordered.includes(:category, :children), limit: 20)

      render inertia: "Community/Sections/Index", props: {
        sections: sections.map { |section| serialize_section(section) },
        pagination: pagy_props(@pagy)
      }
    end

    def show
      section = Community::Section.find_by!(slug: params[:id])
      sort = params[:sort].to_s.presence || "activity"
      filter = params[:filter].to_s.presence
      scope = section.topics.where(status: :published).sorted(sort)
      scope = filter_blocked_topics(scope)
      scope = apply_topic_filter(scope, filter: filter, user: current_user)
      featured = section.topics.featured_topics.pinned_first.limit(5)
      featured = filter_blocked_topics(featured)

      @pagy, topics = pagy(scope, limit: 20)
      read_states = if logged_in?
                      Community::ReadState.where(user: current_user, forum_topic_id: topics.map(&:id)).index_by(&:forum_topic_id)
                    else
                      {}
                    end

      render inertia: "Community/Sections/Show", props: {
        section: {
          name: section.name,
          slug: section.slug,
          description: section.description,
          new_topic_url: logged_in? ? new_forum_topic_path(section_id: section.slug) : nil,
          watching: logged_in? && Community::Subscription.exists?(user: current_user, subscribable: section),
          subscription_url: subscription_forum_section_path(section),
          rss_url: forum_section_rss_path(section)
        },
        featuredTopics: featured.map { |topic| serialize_topic(topic, read_state: read_states[topic.id]) },
        topics: topics.map { |topic| serialize_topic(topic, read_state: read_states[topic.id]) },
        pagination: pagy_props(@pagy),
        sort: sort,
        filter: filter.to_s,
        filterOptions: topic_filter_options,
        canCreateTopic: logged_in?
      }
    end

    def toggle_subscription
      require_login
      section = Community::Section.find_by!(slug: params[:id])
      result = Community::ToggleSectionSubscription.call(user: current_user, section: section)

      if result.success?
        redirect_to forum_section_path(section), notice: result.value[:watching] ? "已关注此分区。" : "已取消关注。"
      else
        redirect_to forum_section_path(section), alert: service_error_message(result)
      end
    end
  end
end
