# frozen_string_literal: true

module Admin
  module Forum
    # XenForo-style forum statistics overview (read-only).
    class StatsController < BaseController
      def index
        day_ago = 1.day.ago
        week_ago = 1.week.ago

        posts = ::Community::Post.where(status: :published)
        topics = ::Community::Topic.where(status: :published)

        render inertia: "Admin/Forum/Stats/Index", props: {
          metrics: [
            metric("topics_total", topics.count),
            metric("posts_total", posts.count),
            metric("members_total", ::User.where(status: :active).count),
            metric("topics_today", topics.where("forum_topics.created_at >= ?", day_ago).count),
            metric("posts_today", posts.where("forum_posts.created_at >= ?", day_ago).count),
            metric("members_today", ::User.where("users.created_at >= ?", day_ago).count),
            metric("posts_week", posts.where("forum_posts.created_at >= ?", week_ago).count),
            metric("reactions_total", ::Community::Reaction.count),
            metric("solved_total", topics.where.not(solved_post_id: nil).count)
          ],
          topPosters: top_posters,
          newestMembers: newest_members
        }
      end

      private

      def metric(key, value)
        { label: forum_t("stats.#{key}"), value: value }
      end

      def top_posters
        ::User.where(status: :active)
          .order(forum_posts_count: :desc)
          .limit(10)
          .map { |user| { username: user.username, posts_count: user.forum_posts_count } }
      end

      def newest_members
        ::User.where(status: :active)
          .order(created_at: :desc)
          .limit(10)
          .map { |user| { username: user.username, joined_at: l(user.created_at.to_date, format: :short) } }
      end
    end
  end
end
