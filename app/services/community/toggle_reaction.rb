# frozen_string_literal: true

module Community
  class ToggleReaction < ApplicationService
    ALLOWED_EMOJI = %w[👍 ❤️ 😂 🎉 👀].freeze

    def self.allowed_emoji
      raw = SiteSetting.get("forum.reaction_emojis", "").to_s
      list = raw.split(/[,\s]+/).map(&:strip).reject(&:blank?).uniq
      list = ALLOWED_EMOJI if list.empty?
      list.first(12)
    end

    def initialize(user:, post:, emoji:)
      @user = user
      @post = post
      @emoji = emoji.to_s
    end

    def call
      return ServiceResult.failure(error: "Post not available.") unless PostAccess.readable?(post: @post, user: @user)
      return ServiceResult.failure(error: "Invalid reaction.") unless self.class.allowed_emoji.include?(@emoji)
      return ServiceResult.failure(error: "cannot_react_to_own_post") if @user.id == @post.user_id
      return ServiceResult.failure(error: "trust_level_cannot_react") unless Community::TrustLevel.can_react?(@user)
      adding = adding?
      return ServiceResult.failure(error: "reaction_daily_limit_reached") if adding && daily_limit_reached?
      return ServiceResult.failure(error: "reaction_too_fast") if adding && cooldown_exceeded?

      added = Community::Reaction.toggle!(@user, @post, @emoji)
      counts = @post.reactions.group(:emoji).count

      Community::NotifyPostReaction.call(post: @post, reactor: @user, emoji: @emoji) if added

      ServiceResult.success(added: added, counts: counts)
    end

    private

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

    # Optional per-minute burst limit, mirroring the post/topic rate limiting.
    # Off by default (forum.max_reactions_per_minute = 0); staff are exempt.
    def cooldown_exceeded?
      return false if @user.permission?("forum.topics.lock") || @user.permission?("admin.access")

      per_minute = SiteSetting.get("forum.max_reactions_per_minute", "0").to_i
      return false if per_minute <= 0

      Administration::RateLimiter.call(key: "forum_reaction:#{@user.id}", limit: per_minute, window: 1.minute).failure?
    end
  end
end
