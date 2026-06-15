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
        categories: Community::Category.ordered.map do |category|
          {
            slug: category.slug,
            name: category.name,
            description: category.description,
            icon: category.icon,
            color_hex: category.color_hex,
            seo_title: category.seo["title"],
            seo_description: category.seo["description"]
          }
        end,
        pagination: pagy_props(@pagy)
      }
    end

    def show
      section = Community::Section.find_by!(slug: params[:id])
      sort = params[:sort].to_s.presence || "activity"
      filter = params[:filter].to_s.presence
      staff = forum_staff?
      base_scope = if filter == "unlisted" && staff
                     section.topics.where(status: :published, unlisted: true)
      else
                     section.topics.published_listed
      end
      scope = preload_topics(base_scope.sorted(sort))
      scope = filter_blocked_topics(scope)
      scope = apply_topic_filter(scope, filter: filter, user: current_user)
      featured = preload_topics(section.topics.featured_topics.pinned_first.limit(5))
      featured = filter_blocked_topics(featured)

      @pagy, topics = pagy(scope, limit: 20)
      read_states = if logged_in?
                      Community::ReadState.where(user: current_user, forum_topic_id: topics.map(&:id) + featured.map(&:id)).index_by(&:forum_topic_id)
      else
                      {}
      end

      render inertia: "Community/Sections/Show", props: {
        section: {
          name: section.name,
          slug: section.slug,
          description: section.description,
          color_hex: section.color_hex,
          icon: section.icon,
          banner_text: section.banner_text,
          link_url: section.link_url,
          link_label: section.link_label,
          read_only: section.read_only?,
          notification_level: logged_in? ? Community::Subscription.find_by(user: current_user, subscribable: section)&.notification_level : nil,
          new_topic_url: logged_in? && section.writable_by?(current_user, :create_topic) && section.allowed?(current_user, :create_topic) ? new_forum_topic_path(section_id: section.slug) : nil,
          watching: logged_in? && Community::Subscription.exists?(user: current_user, subscribable: section),
          muted: logged_in? && Community::SectionMute.exists?(user: current_user, section: section),
          subscription_url: subscription_forum_section_path(section),
          mute_url: mute_forum_section_path(section),
          mark_all_read_url: logged_in? ? mark_all_read_forum_section_path(section) : nil,
          rss_url: forum_section_rss_path(section),
          required_tags: section.required_tags.map { |tag| { name: tag.name, slug: tag.slug, url: forum_tag_path(tag.slug) } },
          required_tag_groups: section.required_tag_groups.map { |g| { name: g.name, slug: g.slug } },
          allowed_tags: section.allowed_tags.map { |tag| { name: tag.name, slug: tag.slug, url: forum_tag_path(tag.slug) } },
          prefix_required: section.prefix_required?
        },
        featuredTopics: serialize_topics(featured, read_states: read_states),
        topics: serialize_topics(topics, read_states: read_states),
        pagination: pagy_props(@pagy),
        sort: sort,
        filter: filter.to_s,
        filterOptions: topic_filter_options(prefixes: Array(section.prefixes), staff: staff),
        canCreateTopic: logged_in? && section.allowed?(current_user, :create_topic) && section.writable_by?(current_user, :create_topic),
        meta: {
          title: section.seo["title"].presence || section.name,
          description: section.seo["description"].presence || section.description&.truncate(160)
        }
      }
    end

    def toggle_subscription
      require_login
      section = Community::Section.find_by!(slug: params[:id])
      result = Community::ToggleSectionSubscription.call(user: current_user, section: section)

      if result.success?
        notice = if result.value[:watching]
                   case result.value[:notification_level]
                   when "tracking" then "已切换为跟踪此分区（仅站内通知）。"
                   else "已关注此分区（即时通知）。"
                   end
        else
                   "已取消关注此分区。"
        end
        redirect_to forum_section_path(section), notice: notice
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
