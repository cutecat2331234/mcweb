# frozen_string_literal: true

module Community
  class SectionsController < ApplicationController
    include Community::TopicFilterable
    include Community::TopicListPreloadable

    def index
      @pagy, sections = pagy(Community::Section.roots.ordered.includes(:category, :children), limit: 20)
      unread_map = if logged_in?
                     sections.each_with_object({}) do |section, hash|
                       hash[section.id] = Community::ReadState.unread_count_for_section(current_user, section)
                       section.children.each do |child|
                         hash[child.id] = Community::ReadState.unread_count_for_section(current_user, child)
                       end
                     end
                   else
                     {}
                   end

      render inertia: "Community/Sections/Index", props: {
        sections: sections.map { |section| serialize_section(section, unread_map: unread_map) },
        pagination: pagy_props(@pagy)
      }
    end

    def show
      section = Community::Section.find_by!(slug: params[:id])
      sort = params[:sort].to_s.presence || "activity"
      filter = params[:filter].to_s.presence
      scope = preload_topics(section.topics.where(status: :published).sorted(sort))
      scope = filter_blocked_topics(scope)
      scope = apply_topic_filter(scope, filter: filter, user: current_user)
      featured = preload_topics(section.topics.featured_topics.pinned_first.limit(5))
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
          muted: logged_in? && Community::SectionMute.exists?(user: current_user, section: section),
          subscription_url: subscription_forum_section_path(section),
          mute_url: mute_forum_section_path(section),
          mark_all_read_url: logged_in? ? mark_all_read_forum_section_path(section) : nil,
          rss_url: forum_section_rss_path(section)
        },
        featuredTopics: featured.map { |topic| serialize_topic(topic, read_state: read_states[topic.id]) },
        topics: topics.map { |topic| serialize_topic(topic, read_state: read_states[topic.id]) },
        pagination: pagy_props(@pagy),
        sort: sort,
        filter: filter.to_s,
        filterOptions: topic_filter_options(prefixes: Array(section.prefixes)),
        canCreateTopic: logged_in? && section.allowed?(current_user, :create_topic),
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

    def mark_all_read
      require_login
      section = Community::Section.find_by!(slug: params[:id])
      result = Community::MarkSectionRead.call(user: current_user, section: section)

      if result.success?
        redirect_to forum_section_path(section), notice: "分区已全部标为已读。"
      else
        redirect_to forum_section_path(section), alert: service_error_message(result)
      end
    end

    def toggle_mute
      require_login
      section = Community::Section.find_by!(slug: params[:id])
      result = Community::ToggleSectionMute.call(user: current_user, section: section)

      if result.success?
        redirect_to forum_section_path(section), notice: result.value[:muted] ? "已静音此分区。" : "已取消静音。"
      else
        redirect_to forum_section_path(section), alert: service_error_message(result)
      end
    end
  end
end
