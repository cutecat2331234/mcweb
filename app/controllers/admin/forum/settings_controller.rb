# frozen_string_literal: true

module Admin
  module Forum
    class SettingsController < Admin::BaseController
      before_action -> { require_admin_module!("system") }
      before_action -> { require_permission("system.settings.manage") }

      FORUM_SETTING_KEYS = %w[
        forum.bump_cooldown_hours
        forum.warning_mute_threshold
        forum.warning_mute_days
        forum.warning_points_expire_days
        forum.require_post_approval_below_tl
        forum.warning_block_post_threshold
        forum.warning_block_links_threshold
        forum.warning_block_pm_threshold
        forum.report_auto_hide_threshold
        forum.auto_close_on_solved
        forum.reaction_emojis
        forum.group_pm_creator_only_add
        forum.saved_search_limit
        forum.saved_search_digest_hour
        forum.digest_hour
        forum.allow_op_close
        forum.min_trust_level_reaction
        forum.saved_search_webhook_secret
        forum.saved_search_webhook_url
        forum.event_webhook_url
        forum.event_webhook_secret
        forum.event_webhook_events
        forum.search_feeds_opml_saved_limit
        forum.search_feeds_opml_history_limit
        webhook.failure_alert_threshold
        webhook.failure_alert_forum_threshold
        webhook.failure_alert_store_threshold
        webhook.failure_alert_email
        webhook.failure_alert_cooldown_hours
      ].freeze

      def show
        render inertia: "Admin/Forum/Settings/Show", props: {
          settings: forum_settings_props,
          testWebhookUrl: test_webhook_admin_forum_settings_path,
          testAllWebhooksUrl: test_all_webhooks_admin_forum_settings_path,
          testEventWebhookUrl: test_event_webhook_admin_forum_settings_path,
          testAllEventWebhooksUrl: test_all_event_webhooks_admin_forum_settings_path,
          testEventWebhookEvents: Community::DispatchForumEventWebhook::EVENT_TYPES,
          testWebhookStatusUrl: webhook_test_status_admin_forum_settings_path,
          savedSearchesForTest: saved_searches_for_test_props,
          lastTestWebhook: WebhookTestDeliveryStatus.forum_last,
          lastTestEventWebhook: WebhookTestDeliveryStatus.forum_event_last
        }
      end

      def update
        settings_params.each do |key, value|
          SiteSetting.set(key, value)
        end

        Administration::AuditLogger.call(
          actor: current_user,
          action: "admin.forum_settings_updated",
          metadata: { keys: settings_params.keys }
        )

        redirect_to admin_forum_settings_path, notice: t("mcweb.flash.forum_settings_saved")
      end

      def test_webhook
        saved_search = find_saved_search_for_test(params[:saved_search_id])
        result = Community::DispatchTestSavedSearchWebhook.call(saved_search: saved_search)
        if result.success?
          label = saved_search ? "「#{saved_search.name}」" : "saved_search.match"
          redirect_to admin_forum_settings_path, notice: t("mcweb.flash.webhook_test_queued", label: label)
        else
          redirect_to admin_forum_settings_path, alert: result.error || t("mcweb.flash.webhook_test_failed")
        end
      end

      def test_all_webhooks
        result = Community::BatchTestSavedSearchWebhooks.call(user: current_user)
        if result.success?
          redirect_to admin_forum_settings_path,
                      notice: t("mcweb.flash.webhook_batch_test_queued", queued: result.value[:queued], total: result.value[:total])
        else
          redirect_to admin_forum_settings_path, alert: result.error || t("mcweb.flash.webhook_batch_test_failed")
        end
      end

      def test_event_webhook
        event_type = params[:event].to_s.presence || "topic.created"
        result = Community::DispatchTestForumEventWebhook.call(event_type: event_type)
        if result.success?
          redirect_to admin_forum_settings_path, notice: t("mcweb.flash.webhook_test_queued", label: result.value[:event_type])
        else
          redirect_to admin_forum_settings_path, alert: result.error || t("mcweb.flash.webhook_test_failed")
        end
      end

      def test_all_event_webhooks
        result = Community::BatchTestForumEventWebhooks.call
        if result.success?
          redirect_to admin_forum_settings_path,
                      notice: t("mcweb.flash.webhook_batch_event_test_queued", queued: result.value[:queued], total: result.value[:total])
        else
          redirect_to admin_forum_settings_path, alert: result.error || t("mcweb.flash.webhook_batch_test_failed")
        end
      end

      def webhook_test_status
        render json: {
          lastTestWebhook: WebhookTestDeliveryStatus.forum_last,
          lastTestEventWebhook: WebhookTestDeliveryStatus.forum_event_last
        }
      end

    private

      def forum_settings_props
        FORUM_SETTING_KEYS.map do |key|
          {
            key: key,
            value: SiteSetting.get(key, default_for(key)).to_s,
            label: setting_label(key),
            hint: setting_hint(key),
            input_type: setting_input_type(key)
          }
        end
      end

      def settings_params
        allowed = FORUM_SETTING_KEYS.index_with { |_k| nil }
        params.fetch(:settings, {}).permit(*allowed.keys).to_h
      end

      def default_for(key)
        case key
        when "forum.group_pm_creator_only_add" then "false"
        when "forum.auto_close_on_solved" then "0"
        when "forum.bump_cooldown_hours" then "24"
        when "forum.warning_mute_threshold" then "10"
        when "forum.warning_mute_days" then "7"
        when "forum.warning_points_expire_days" then "90"
        when "forum.require_post_approval_below_tl" then "1"
        when "forum.report_auto_hide_threshold" then "5"
        when "forum.reaction_emojis" then "👍,❤️,😂,🎉,👀"
        when "forum.saved_search_limit" then "20"
        when "forum.saved_search_digest_hour" then "9"
        when "forum.digest_hour" then "8"
        when "forum.allow_op_close" then "true"
        when "forum.min_trust_level_reaction" then "0"
        when "forum.saved_search_webhook_secret" then ""
        when "forum.saved_search_webhook_url" then ""
        when "forum.event_webhook_url" then ""
        when "forum.event_webhook_secret" then ""
        when "forum.event_webhook_events" then Community::DispatchForumEventWebhook::DEFAULT_EVENTS
        when "forum.search_feeds_opml_saved_limit" then "50"
        when "forum.search_feeds_opml_history_limit" then "20"
        when "webhook.failure_alert_threshold" then "5"
        when "webhook.failure_alert_forum_threshold" then "5"
        when "webhook.failure_alert_store_threshold" then "5"
        when "webhook.failure_alert_email" then ""
        when "webhook.failure_alert_cooldown_hours" then "6"
        else "0"
        end
      end

      def setting_label(key)
        labels = I18n.t("mcweb.admin.forum.settings.labels")
        return key unless labels.is_a?(Hash)

        labels[key.to_sym] || labels[key] || key
      end

      def setting_hint(key)
        hints = I18n.t("mcweb.admin.forum.settings.hints")
        return nil unless hints.is_a?(Hash)

        hints[key.to_sym] || hints[key]
      end

      def setting_input_type(key)
        return "boolean" if key == "forum.group_pm_creator_only_add"
        return "boolean" if key == "forum.allow_op_close"
        return "text" if key == "forum.saved_search_webhook_secret"
        return "text" if key == "forum.saved_search_webhook_url"
        return "text" if key == "forum.event_webhook_secret"
        return "text" if key == "forum.event_webhook_url"
        return "text" if key == "forum.event_webhook_events"
        return "text" if key == "webhook.failure_alert_email"

        "text"
      end

      def saved_searches_for_test_props
        current_user.forum_saved_searches.recent.limit(20).map do |search|
          { id: search.id, name: search.name }
        end
      end

      def find_saved_search_for_test(id)
        return nil if id.blank?

        current_user.forum_saved_searches.find_by(id: id)
      end
    end
  end
end
