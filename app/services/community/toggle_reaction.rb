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
      return ServiceResult.failure(error: "Invalid reaction.") unless ALLOWED_EMOJI.include?(@emoji)

      added = Community::Reaction.toggle!(@user, @post, @emoji)
      counts = @post.reactions.group(:emoji).count

      ServiceResult.success(added: added, counts: counts)
    end
  end
end
