# frozen_string_literal: true

module Admin
  module Forum
    class SettingsController < BaseController
      before_action -> { require_permission("system.settings.manage") }

      FORUM_SETTING_KEYS = %w[
        forum.bump_cooldown_hours
        forum.warning_mute_threshold
        forum.warning_mute_days
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
          testWebhookStatusUrl: webhook_test_status_admin_forum_settings_path,
          savedSearchesForTest: saved_searches_for_test_props,
          lastTestWebhook: WebhookTestDeliveryStatus.forum_last
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

      def webhook_test_status
        render json: { lastTestWebhook: WebhookTestDeliveryStatus.forum_last }
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
        when "forum.report_auto_hide_threshold" then "5"
        when "forum.reaction_emojis" then "👍,❤️,😂,🎉,👀"
        when "forum.saved_search_limit" then "20"
        when "forum.saved_search_digest_hour" then "9"
        when "forum.digest_hour" then "8"
        when "forum.allow_op_close" then "true"
        when "forum.min_trust_level_reaction" then "0"
        when "forum.saved_search_webhook_secret" then ""
        when "forum.saved_search_webhook_url" then ""
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
        {
          "forum.bump_cooldown_hours" => "主题顶起冷却（小时）",
          "forum.warning_mute_threshold" => "警告自动禁言阈值",
          "forum.warning_mute_days" => "警告禁言天数",
          "forum.warning_block_post_threshold" => "警告禁止发帖阈值",
          "forum.warning_block_links_threshold" => "警告禁止链接阈值",
          "forum.warning_block_pm_threshold" => "警告禁止私信阈值",
          "forum.report_auto_hide_threshold" => "举报自动隐藏阈值",
          "forum.auto_close_on_solved" => "解决后自动关闭主题",
          "forum.reaction_emojis" => "可用反应表情（逗号分隔）",
          "forum.group_pm_creator_only_add" => "仅群主可添加群成员",
          "forum.saved_search_limit" => "保存搜索数量上限",
          "forum.saved_search_digest_hour" => "保存搜索摘要发送时间（小时）",
          "forum.digest_hour" => "论坛通知摘要发送时间（小时）",
          "forum.allow_op_close" => "允许楼主关闭自己的主题",
          "forum.min_trust_level_reaction" => "使用反应所需的最低信任等级",
          "forum.saved_search_webhook_secret" => "保存搜索 Webhook 密钥",
          "forum.saved_search_webhook_url" => "保存搜索 Webhook URL（测试/全局）",
          "forum.search_feeds_opml_saved_limit" => "合并 OPML 保存搜索上限",
          "forum.search_feeds_opml_history_limit" => "合并 OPML 搜索历史上限",
          "webhook.failure_alert_threshold" => "Webhook 失败告警阈值（24h，兼容）",
          "webhook.failure_alert_forum_threshold" => "论坛 Webhook 失败告警阈值（24h）",
          "webhook.failure_alert_store_threshold" => "商城 Webhook 失败告警阈值（24h）",
          "webhook.failure_alert_email" => "Webhook 失败告警邮箱",
          "webhook.failure_alert_cooldown_hours" => "Webhook 告警冷却（小时）"
        }[key] || key
      end

      def setting_hint(key)
        {
          "forum.group_pm_creator_only_add" => "开启后，群聊中只有创建者可邀请新成员（对标 Discourse 群组策略）。",
          "forum.auto_close_on_solved" => "设为 1 时，主题标记为已解决后自动锁定。",
          "forum.report_auto_hide_threshold" => "帖子被举报达到此次数后自动隐藏待审。",
          "forum.reaction_emojis" => "用户可对帖子使用的表情列表。",
          "forum.saved_search_limit" => "每位用户可保存的搜索数量，0 表示不限制。",
          "forum.saved_search_digest_hour" => "每日发送保存搜索摘要邮件的小时（0–23，服务器时区）。任务每小时检查一次。",
          "forum.digest_hour" => "每日发送论坛通知摘要邮件的小时（0–23）。任务每小时检查一次。",
          "forum.allow_op_close" => "设为 false 时楼主无法自行关闭主题。",
          "forum.min_trust_level_reaction" => "信任等级低于此值的用户无法对帖子添加反应。",
          "forum.saved_search_webhook_secret" => "用于 X-McWeb-Signature HMAC 签名的密钥，可选。",
          "forum.saved_search_webhook_url" => "用于管理后台测试投递与全局 Hook，留空则无法发送测试。",
          "forum.search_feeds_opml_saved_limit" => "合并 OPML 导出时最多包含的保存搜索数量（1–100）。",
          "forum.search_feeds_opml_history_limit" => "合并 OPML 导出时最多包含的搜索历史数量（1–50）。",
          "webhook.failure_alert_threshold" => "旧版统一阈值，论坛/商城未单独配置时回退使用。0 表示关闭。",
          "webhook.failure_alert_forum_threshold" => "近 24 小时论坛 Webhook 失败达到此值时告警，0 表示不检查论坛。",
          "webhook.failure_alert_store_threshold" => "近 24 小时商城 Webhook 失败达到此值时告警，0 表示不检查商城。",
          "webhook.failure_alert_email" => "接收 Webhook 失败告警的管理员邮箱。",
          "webhook.failure_alert_cooldown_hours" => "两次告警之间的最短间隔，避免重复打扰。"
        }[key]
      end

      def setting_input_type(key)
        return "boolean" if key == "forum.group_pm_creator_only_add"
        return "boolean" if key == "forum.allow_op_close"
        return "text" if key == "forum.saved_search_webhook_secret"
        return "text" if key == "forum.saved_search_webhook_url"
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
