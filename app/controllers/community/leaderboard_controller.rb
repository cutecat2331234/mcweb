# frozen_string_literal: true

module Community
  class LeaderboardController < ApplicationController
    PERIODS = %w[all week month].freeze
    METRICS = %w[posts likes score].freeze
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
      case metric
      when "likes"
        rel = Community::Reaction.joins(:post).where(forum_posts: { status: "published" })
        rel = rel.where("forum_reactions.created_at >= ?", since) if since
        rel.group("forum_posts.user_id").order(Arel.sql("COUNT(forum_reactions.id) DESC")).limit(LIMIT).count("forum_reactions.id")
      when "score"
        ranked_reaction_scores(since)
      else
        rel = Community::Post.where(status: "published")
        rel = rel.where("forum_posts.created_at >= ?", since) if since
        rel.group(:user_id).order(Arel.sql("COUNT(forum_posts.id) DESC")).limit(LIMIT).count
      end
    end

    # Rank by weighted reaction score (forum.reaction_scores) instead of raw count.
    # Counts are grouped per (user, emoji) and weighted in Ruby so the dynamic
    # weight map applies; unlisted emoji weigh 1 (matching Reaction.score_for).
    def ranked_reaction_scores(since)
      map = Community::Reaction.score_map
      rel = Community::Reaction.joins(:post).where(forum_posts: { status: "published" })
      rel = rel.where("forum_reactions.created_at >= ?", since) if since

      scores = Hash.new(0)
      rel.group("forum_posts.user_id", "forum_reactions.emoji").count.each do |(user_id, emoji), count|
        scores[user_id] += count * map.fetch(emoji.to_s, 1)
      end
      scores.sort_by { |_user_id, score| -score }.first(LIMIT).to_h
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
