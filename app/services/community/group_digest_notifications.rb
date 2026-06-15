# frozen_string_literal: true

module Community
  class GroupDigestNotifications
    TYPE_LABELS = {
      "forum.topic_reply" => "主题回复",
      "forum.mention" => "@提及",
      "forum.section_topic" => "分区新主题",
      "forum.private_message" => "私信",
      "forum.followed_topic" => "关注用户新主题",
      "forum.followed_reply" => "关注用户回复",
      "forum.tag_topic" => "标签新主题",
      "forum.reaction" => "帖子反应",
      "forum.quote" => "帖子引用",
      "forum.topic_solved" => "主题已解决",
      "forum.saved_search_match" => "保存搜索匹配",
      "forum.badge" => "获得徽章",
      "forum.trust_level" => "信任等级",
      "forum.topic_assigned" => "主题指派",
      "forum.post_edited" => "帖子编辑",
      "forum.topic_invite" => "主题邀请",
      "forum.poll_closed" => "投票关闭",
      "forum.here" => "@here 提及"
    }.freeze

    def self.call(notifications)
      new(notifications).sections
    end

    def initialize(notifications)
      @notifications = Array(notifications)
    end

    def sections
      grouped = @notifications.group_by(&:notification_type)
      grouped.map do |type, items|
        {
          type: type,
          label: TYPE_LABELS[type] || type.to_s.humanize,
          notifications: items.sort_by(&:created_at).reverse
        }
      end.sort_by { |section| -section[:notifications].first.created_at.to_i }
    end
  end
end
