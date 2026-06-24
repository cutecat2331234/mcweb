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
      forum.followed_reply
      forum.tag_topic
      forum.reaction
      forum.quote
      forum.topic_solved
      forum.badge
      forum.trust_level
      forum.bookmark_reminder
      forum.saved_search_match
      forum.post_edited
      forum.user_warning
      forum.topic_invite
      forum.conversation_invite
      forum.topic_assigned
      forum.poll_closed
      forum.here
      forum.post_pending
      forum.post_rejected
    ].freeze

    DIGEST_OPTIONS = %w[none daily weekly].freeze
    WATCH_EMAIL_MODES = %w[instant digest_only none].freeze

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
        watch_email_mode: current_user.forum_watch_email_mode,
        watch_email_mode_options: WATCH_EMAIL_MODES.map { |v| { value: v, label: watch_email_mode_label(v) } },
        notificationLevelGuide: Community::SubscriptionLevelOptions.guide,
        savedSearches: serialize_saved_searches_for_preferences,
        savedSearchesOpmlUrl: Community::SavedSearchPresenter.opml_path(current_user),
        watchingOpmlUrl: forum_watching_opml_path(token: Community::WatchingOpmlToken.generate(current_user)),
        savedSearchWebhookDeliveries: serialize_saved_search_webhook_deliveries
      }
    end

    def update
      NOTIFICATION_TYPES.each do |type|
        CHANNELS.each do |channel|
          enabled = params.dig(:preferences, type, channel)
          next if enabled.nil?

          NotificationPreference.set!(
            current_user,
            channel: channel,
            notification_type: type,
            enabled: ActiveModel::Type::Boolean.new.cast(enabled)
          )
        end
      end

      if params[:digest_frequency].present? && DIGEST_OPTIONS.include?(params[:digest_frequency])
        current_user.update!(forum_digest_frequency: params[:digest_frequency])
      end

      if params.key?(:digest_watched_only)
        current_user.update!(forum_digest_watched_only: ActiveModel::Type::Boolean.new.cast(params[:digest_watched_only]))
      end

      if params[:watch_email_mode].present? && WATCH_EMAIL_MODES.include?(params[:watch_email_mode])
        current_user.update!(forum_watch_email_mode: params[:watch_email_mode])
      end

      redirect_to forum_preferences_path, notice: t("mcweb.flash.preferences_saved")
    end

    private

    def notification_label(type)
      Community::NotificationTypeLabels.label_for(type)
    end

    def digest_label(value)
      I18n.t("mcweb.forum.digest.#{value}", default: value)
    end

    def watch_email_mode_label(value)
      I18n.t("mcweb.forum.watch_email_mode.#{value}", default: value)
    end

    def serialize_saved_searches_for_preferences
      current_user.forum_saved_searches.recent.limit(20).map do |search|
        {
          id: search.id,
          name: search.name,
          query: search.query,
          notify_daily: search.notify_daily?,
          notify_in_app: search.notify_in_app?,
          filter_labels: Community::SavedSearchFilterSummary.call(search),
          url: forum_search_path(Community::SavedSearchPresenter.url_params(search)),
          rss_url: Community::SavedSearchPresenter.rss_path(search),
          webhook_url: search.webhook_url,
          update_url: forum_saved_search_path(search),
          delete_url: forum_saved_search_path(search)
        }
      end
    end

    def saved_search_url_params(search)
      Community::SavedSearchPresenter.url_params(search)
    end

    def serialize_saved_search_webhook_deliveries
      search_ids = current_user.forum_saved_searches.pluck(:id)
      return [] if search_ids.empty?

      searches_by_id = current_user.forum_saved_searches.index_by(&:id)
      Community::SavedSearchWebhookDelivery
        .where(saved_search_id: search_ids)
        .recent
        .limit(20)
        .map do |delivery|
          search = searches_by_id[delivery.saved_search_id]
          {
            id: delivery.id,
            search_name: search&.name,
            event_type: delivery.event_type,
            status: delivery.status,
            response_code: delivery.response_code,
            created_at: l(delivery.created_at, format: :short),
            retry_url: delivery.status == "failed" && delivery.request_payload.present? ? forum_retry_saved_search_webhook_delivery_path(delivery) : nil
          }
        end
    end
  end
end
