# frozen_string_literal: true

module Community
  class ToggleReaction < ApplicationService
    ALLOWED_EMOJI = %w[👍 ❤️ 😂 🎉 👀].freeze

    def self.allowed_emoji
      # Managed reaction types take precedence when configured (XenForo-style);
      # otherwise fall back to the legacy SiteSetting / built-in defaults.
      return Community::ReactionType.emojis if Community::ReactionType.configured?

      raw = SiteSetting.get("forum.reaction_emojis", "").to_s
      list = raw.split(/[,\s]+/).map(&:strip).reject(&:blank?).uniq
      list = ALLOWED_EMOJI if list.empty?
      list.first(12)
    end

    def initialize(user:, post:, emoji:, ip_address: nil)
      @user = user
      @post = post
      @emoji = emoji.to_s
      @ip_address = ip_address
    end

    def call
      return ServiceResult.failure(error: "Post not available.") unless PostAccess.readable?(post: @post, user: @user)
      return ServiceResult.failure(error: "This topic is archived.") if @post.topic.archived_at.present?
      return ServiceResult.failure(error: "Invalid reaction.") unless self.class.allowed_emoji.include?(@emoji)
      return ServiceResult.failure(error: "cannot_react_to_own_post") if @user.id == @post.user_id
      return ServiceResult.failure(error: "trust_level_cannot_react") unless Community::TrustLevel.can_react?(@user)
      adding = adding?
      return ServiceResult.failure(error: "reaction_daily_limit_reached") if adding && daily_limit_reached?
      if adding
        rate_limit_result = reaction_rate_limit
        return rate_limit_result if rate_limit_result.failure?
      end

      added = Community::Reaction.toggle!(@user, @post, @emoji)
      counts = @post.reactions.group(:emoji).count

      Community::NotifyPostReaction.call(post: @post, reactor: @user, emoji: @emoji) if added
      award_reaction_points if added

      Mcweb::Events.publish(
        added ? "forum.reaction.added" : "forum.reaction.removed",
        post: @post, user: @user, emoji: @emoji, counts: counts
      )
      ServiceResult.success(added: added, counts: counts)
    end

    private

    # Reward the POST AUTHOR (not the reactor) when their post receives a reaction.
    # dedupe_token "reaction:<post_id>:<reactor_id>" ensures each distinct reactor
    # awards the author at most once per post lifetime, surviving like/unlike/relike
    # (the token is independent of the toggled Reaction row). Cancelling does not
    # deduct. Self-reactions are already blocked above.
    def award_reaction_points
      Community::AwardPoints.for_rule(
        user: @post.user,
        rule: "reaction_received",
        dedupe_token: "reaction:#{@post.id}:#{@user.id}",
        default: 2
      )
    rescue StandardError => e
      Rails.logger.error("[AwardPoints] reaction_received failed for post=#{@post.id} reactor=#{@user.id}: #{e.class}: #{e.message}")
    end

    def adding?
      !@post.reactions.exists?(user: @user, emoji: @emoji)
    end

    # Discourse-style daily like cap, scaled by trust level. Off by default
    # (forum.max_daily_reactions = 0 => unlimited); staff are exempt.
    def daily_limit_reached?
      return false if @user.permission?("forum.topics.lock") || @user.permission?("admin.access")

      base = SiteSetting.get("forum.max_daily_reactions", "0").to_i
      return false if base <= 0

      limit = base * [ Community::TrustLevel.level_for(@user), 1 ].max
      Community::Reaction.where(user: @user).where("created_at >= ?", Time.current.beginning_of_day).count >= limit
    end

    # The account burst limit remains compatible with the optional forum
    # setting, while AbuseRateLimit also applies a conservative IP ceiling.
    # Staff are exempt from both dimensions.
    def reaction_rate_limit
      if @user.permission?("forum.topics.lock") || @user.permission?("admin.access")
        return ServiceResult.success
      end

      Administration::AbuseRateLimit.call(
        action: :reaction,
        account: @user,
        ip_address: @ip_address
      )
    end
  end
end
