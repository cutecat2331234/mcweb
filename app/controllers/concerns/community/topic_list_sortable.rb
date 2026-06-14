# frozen_string_literal: true

module Community
  module TopicListSortable
    extend ActiveSupport::Concern

    private

    def apply_forum_topic_sort(scope, sort)
      case sort.to_s
      when "hot"
        scope.reorder(Arel.sql(<<~SQL.squish))
          forum_topics.pinned DESC,
          (forum_topics.replies_count * 3 + forum_topics.views_count)::float
          / POWER(GREATEST(EXTRACT(EPOCH FROM (NOW() - forum_topics.last_posted_at)) / 3600.0, 0) + 2, 1.2) DESC
        SQL
      when "replies"
        scope.reorder("forum_topics.pinned DESC, forum_topics.replies_count DESC, forum_topics.last_posted_at DESC")
      when "newest"
        scope.reorder("forum_topics.pinned DESC, forum_topics.created_at DESC")
      else
        scope.reorder("forum_topics.pinned DESC, forum_topics.last_posted_at DESC")
      end
    end
  end
end
