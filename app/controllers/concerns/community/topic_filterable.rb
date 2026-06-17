# frozen_string_literal: true

module Community
  module TopicFilterable
    extend ActiveSupport::Concern

    private

    def apply_topic_filter(scope, filter:, user:)
      case filter.to_s
      when "unsolved"
        scope.where(solved_post_id: nil)
      when "solved"
        scope.where.not(solved_post_id: nil)
      when "solved_mine"
        user ? scope.where(user: user).where.not(solved_post_id: nil) : scope.none
      when "mine"
        user ? scope.where(user: user) : scope.none
      when "participated"
        if user
          topic_ids = Community::Post.where(user: user, status: :published).select(:forum_topic_id)
          scope.where(id: topic_ids)
        else
          scope.none
        end
      when "unread"
        if user
          scope.where(id: Community::ReadState.with_unread_for(user).select(:forum_topic_id))
        else
          scope.none
        end
      when "no_replies"
        scope.where(replies_count: 0)
      when "locked"
        scope.where(locked: true)
      when "unlocked"
        scope.where(locked: false)
      when "pinned"
        scope.where(pinned: true)
      when "wiki"
        scope.where(wiki: true)
      when "featured"
        scope.where(featured: true)
      when "announcement"
        scope.where(global_announcement: true)
      when "unlisted"
        scope.where(unlisted: true)
      when "archived"
        user&.permission?("forum.topics.lock") ? scope.where.not(archived_at: nil) : scope.none
      when "has_poll"
        scope.where(id: Community::Poll.select(:forum_topic_id))
      when "assigned"
        scope.where.not(assigned_to_id: nil)
      when "unassigned"
        scope.where(assigned_to_id: nil)
      when "assigned_mine"
        user ? scope.where(assigned_to: user) : scope.none
      when /\Aprefix:(.+)\z/
        scope.where(prefix: Regexp.last_match(1))
      else
        scope
      end
    end

    def topic_filter_options(prefixes: [], staff: false)
      options = [
        { value: "", label: "全部" },
        { value: "unsolved", label: "未解决" },
        { value: "solved", label: "已解决" },
        { value: "solved_mine", label: "我已解决" },
        { value: "mine", label: "我的主题" },
        { value: "participated", label: "我参与的" },
        { value: "unread", label: "未读" },
        { value: "no_replies", label: "零回复" },
        { value: "locked", label: "已锁定" },
        { value: "unlocked", label: "未锁定" },
        { value: "pinned", label: "已置顶" },
        { value: "wiki", label: "Wiki 主题" },
        { value: "featured", label: "精选主题" },
        { value: "announcement", label: "全站公告" },
        { value: "has_poll", label: "含投票" }
      ]
      if staff
        options += [
          { value: "assigned", label: "已指派" },
          { value: "unassigned", label: "未指派" },
          { value: "assigned_mine", label: "指派给我" }
        ]
      end
      options << { value: "unlisted", label: "未列出" } if staff
      options << { value: "archived", label: "已归档" } if staff
      prefixes.each do |prefix|
        options << { value: "prefix:#{prefix}", label: "前缀：#{prefix}" }
      end
      options
    end

    def forum_staff?(user = current_user)
      user&.permission?("forum.topics.lock")
    end
  end
end
