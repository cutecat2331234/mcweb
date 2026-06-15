# frozen_string_literal: true

module Community
  class ToggleReaction < ApplicationService
    ALLOWED_EMOJI = %w[👍 ❤️ 😂 🎉 👀].freeze

    def initialize(user:, post:, emoji:)
      @user = user
      @post = post
      @emoji = emoji.to_s
    end

    def call
      return ServiceResult.failure(error: "Topic not available.") unless PollParticipation.visible?(topic: @post.topic, user: @user)
      return ServiceResult.failure(error: "Invalid reaction.") unless ALLOWED_EMOJI.include?(@emoji)
      return ServiceResult.failure(error: "不能给自己的帖子点反应。") if @user.id == @post.user_id
      return ServiceResult.failure(error: "你的信任等级不足以使用反应功能。") unless Community::TrustLevel.can_react?(@user)

      added = Community::Reaction.toggle!(@user, @post, @emoji)
      counts = @post.reactions.group(:emoji).count

      Community::NotifyPostReaction.call(post: @post, reactor: @user, emoji: @emoji) if added

      ServiceResult.success(added: added, counts: counts)
    end
  end
end
