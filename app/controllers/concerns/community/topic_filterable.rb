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
      else
        scope
      end
    end

    def topic_filter_options
      [
        { value: "", label: "全部" },
        { value: "unsolved", label: "未解决" },
        { value: "solved", label: "已解决" },
        { value: "mine", label: "我的主题" },
        { value: "participated", label: "我参与的" },
        { value: "unread", label: "未读" },
        { value: "no_replies", label: "零回复" }
      ]
    end
  end
end
