# frozen_string_literal: true

module Community
  class LeaderboardController < ApplicationController
    PERIODS = %w[all week month].freeze
    METRICS = %w[posts likes].freeze
    LIMIT = 50

    def index
      period = PERIODS.include?(params[:period].to_s) ? params[:period].to_s : "all"
      metric = METRICS.include?(params[:metric].to_s) ? params[:metric].to_s : "posts"
      since = window_start(period)

      counts = ranked_counts(metric, since)
      users = User.where(id: counts.keys, status: :active).index_by(&:id)

      ranked = counts.filter_map { |user_id, score| (u = users[user_id]) ? [ u, score ] : nil }
      entries = ranked.each_with_index.map do |(user, score), index|
        serialize_entry(user, rank: index + 1, score: score)
      end

      render inertia: "Community/Leaderboard/Index", props: {
        entries: entries,
        period: period,
        metric: metric
      }
    end

    private

    def window_start(period)
      case period
      when "week" then 1.week.ago
      when "month" then 1.month.ago
      end
    end

    def ranked_counts(metric, since)
      if metric == "likes"
        rel = Community::Reaction.joins(:post).where(forum_posts: { status: "published" })
        rel = rel.where("forum_reactions.created_at >= ?", since) if since
        rel.group("forum_posts.user_id").order(Arel.sql("COUNT(forum_reactions.id) DESC")).limit(LIMIT).count("forum_reactions.id")
      else
        rel = Community::Post.where(status: "published")
        rel = rel.where("forum_posts.created_at >= ?", since) if since
        rel.group(:user_id).order(Arel.sql("COUNT(forum_posts.id) DESC")).limit(LIMIT).count
      end
    end

    def serialize_entry(user, rank:, score:)
      trust = Community::TrustLevel.level_info(user)
      {
        rank: rank,
        score: score,
        username: user.username,
        display_name: user.display_name,
        avatar_url: user.avatar_url,
        profile_url: forum_user_path(user.username),
        trust_level: trust[:level],
        trust_name: trust[:name]
      }
    end
  end
end
