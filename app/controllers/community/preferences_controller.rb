# frozen_string_literal: true

module Community
  class PreferencesController < ApplicationController
    before_action :require_login

    NOTIFICATION_TYPES = %w[
      forum.topic_reply
      forum.mention
      forum.section_topic
      forum.private_message
      forum.followed_topic
      forum.tag_topic
      forum.reaction
      forum.quote
      forum.topic_solved
      forum.badge
      forum.trust_level
      forum.bookmark_reminder
      forum.post_edited
      forum.user_warning
      forum.topic_invite
      forum.topic_assigned
      forum.here
    ].freeze

    DIGEST_OPTIONS = %w[none daily weekly].freeze

    CHANNELS = %w[in_app email].freeze

    def show
      prefs = NOTIFICATION_TYPES.map do |type|
        {
          notification_type: type,
          label: notification_label(type),
          in_app: NotificationPreference.enabled?(current_user, channel: "in_app", notification_type: type),
          email: NotificationPreference.enabled?(current_user, channel: "email", notification_type: type)
        }
      end

      render inertia: "Community/Preferences/Show", props: {
        preferences: prefs,
        digest_frequency: current_user.forum_digest_frequency,
        digest_watched_only: current_user.forum_digest_watched_only?,
        digest_options: DIGEST_OPTIONS.map { |v| { value: v, label: digest_label(v) } },
        savedSearches: serialize_saved_searches_for_preferences
      }
    end

    def update
      NOTIFICATION_TYPES.each do |type|
        CHANNELS.each do |channel|
          enabled = ActiveModel::Type::Boolean.new.cast(params.dig(:preferences, type, channel))
          NotificationPreference.set!(
            current_user,
            channel: channel,
            notification_type: type,
            enabled: enabled
          )
        end
      end

      if params[:digest_frequency].present? && DIGEST_OPTIONS.include?(params[:digest_frequency])
        current_user.update!(forum_digest_frequency: params[:digest_frequency])
      end

      if params.key?(:digest_watched_only)
        current_user.update!(forum_digest_watched_only: ActiveModel::Type::Boolean.new.cast(params[:digest_watched_only]))
      end

      redirect_to forum_preferences_path, notice: "通知偏好已保存。"
    end

    private

    def notification_label(type)
      {
        "forum.topic_reply" => "主题回复",
        "forum.mention" => "@提及",
        "forum.section_topic" => "关注分区新主题",
        "forum.private_message" => "私信",
        "forum.followed_topic" => "关注用户新主题",
        "forum.tag_topic" => "关注标签新主题",
        "forum.reaction" => "帖子反应",
        "forum.quote" => "帖子引用",
        "forum.topic_solved" => "主题已解决",
        "forum.badge" => "获得徽章",
        "forum.trust_level" => "信任等级提升",
        "forum.bookmark_reminder" => "书签提醒",
        "forum.post_edited" => "帖子编辑通知",
        "forum.user_warning" => "社区警告",
        "forum.topic_invite" => "主题邀请关注",
        "forum.topic_assigned" => "主题指派",
        "forum.here" => "@here 提及"
      }[type] || type.humanize
    end

    def digest_label(value)
      { "none" => "关闭摘要", "daily" => "每日摘要", "weekly" => "每周摘要" }[value] || value
    end

    def serialize_saved_searches_for_preferences
      current_user.forum_saved_searches.recent.limit(20).map do |search|
        {
          id: search.id,
          name: search.name,
          query: search.query,
          notify_daily: search.notify_daily?,
          filter_labels: Community::SavedSearchFilterSummary.call(search),
          url: forum_search_path(Community::SavedSearchPresenter.url_params(search)),
          rss_url: Community::SavedSearchPresenter.rss_path(search),
          update_url: forum_saved_search_path(search),
          delete_url: forum_saved_search_path(search)
        }
      end
    end

    def saved_search_url_params(search)
      Community::SavedSearchPresenter.url_params(search)
    end
  end
end
