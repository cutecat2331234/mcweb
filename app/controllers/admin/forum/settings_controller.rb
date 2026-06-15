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
      ].freeze

      def show
        render inertia: "Admin/Forum/Settings/Show", props: {
          settings: forum_settings_props
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

        redirect_to admin_forum_settings_path, notice: "论坛设置已保存。"
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
          "forum.saved_search_digest_hour" => "保存搜索摘要发送时间（小时）"
        }[key] || key
      end

      def setting_hint(key)
        {
          "forum.group_pm_creator_only_add" => "开启后，群聊中只有创建者可邀请新成员（对标 Discourse 群组策略）。",
          "forum.auto_close_on_solved" => "设为 1 时，主题标记为已解决后自动锁定。",
          "forum.report_auto_hide_threshold" => "帖子被举报达到此次数后自动隐藏待审。",
          "forum.reaction_emojis" => "用户可对帖子使用的表情列表。",
          "forum.saved_search_limit" => "每位用户可保存的搜索数量，0 表示不限制。",
          "forum.saved_search_digest_hour" => "每日发送保存搜索摘要邮件的小时（0–23，服务器时区）。任务每小时检查一次。"
        }[key]
      end

      def setting_input_type(key)
        key == "forum.group_pm_creator_only_add" ? "boolean" : "text"
      end
    end
  end
end
