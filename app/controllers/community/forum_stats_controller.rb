# frozen_string_literal: true

module Community
  # XenForo-style public "Members > Statistics" overview.
  class ForumStatsController < ApplicationController
    def index
      day_ago = 1.day.ago
      week_ago = 1.week.ago
      posts = listed_posts
      topics = Community::ForumAccess.listed_topic_scope(
        relation: Community::Topic.all,
        user: current_user
      )
      reactions = Community::Reaction.where(forum_post_id: posts.select(:id))

      render inertia: "Community/Stats/Index", props: {
        metrics: [
          metric("topics", topics.count),
          metric("posts", posts.count),
          metric("members", User.where(status: :active).count),
          metric("topics_today", topics.where("forum_topics.created_at >= ?", day_ago).count),
          metric("posts_week", posts.where("forum_posts.created_at >= ?", week_ago).count),
          metric("reactions", reactions.count)
        ],
        topPosters: top_posters,
        mostReacted: most_reacted,
        newestMembers: newest_members
      }
    end

    private

    def metric(key, value)
      { label: t("mcweb.forum.stats.#{key}"), value: value }
    end

    def top_posters
      counts = listed_posts
        .group(:user_id)
        .order(Arel.sql("COUNT(forum_posts.id) DESC"))
        .limit(10)
        .count
      users = User.where(id: counts.keys, status: :active).index_by(&:id)
      counts.filter_map { |user_id, count| (user = users[user_id]) && serialize_member(user, value: count) }
    end

    def most_reacted
      counts = Community::Reaction.joins(:post)
        .where(forum_post_id: listed_posts.select(:id))
        .group("forum_posts.user_id")
        .order(Arel.sql("COUNT(forum_reactions.id) DESC"))
        .limit(10)
        .count("forum_reactions.id")
      users = User.where(id: counts.keys, status: :active).index_by(&:id)
      counts.filter_map { |user_id, count| (u = users[user_id]) && serialize_member(u, value: count) }
    end

    def listed_posts
      @listed_posts ||= Community::ForumAccess.listed_post_scope(
        relation: Community::Post.all,
        user: current_user
      )
    end

    def newest_members
      User.where(status: :active)
        .order(created_at: :desc)
        .limit(10)
        .map { |user| serialize_member(user, value: l(user.created_at.to_date, format: :short)) }
    end

    def serialize_member(user, value:)
      {
        username: user.username,
        display_name: user.display_name,
        avatar_url: user.avatar_url,
        url: forum_user_path(user.username),
        value: value
      }
    end
  end
end
