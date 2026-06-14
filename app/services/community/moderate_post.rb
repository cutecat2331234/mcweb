# frozen_string_literal: true

module Community
  class ModeratePost < ApplicationService
    def initialize(user:, post:, action:)
      @user = user
      @post = post
      @action = action.to_s
    end

    def call
      unless @user.permission?("forum.topics.lock")
        return ServiceResult.failure(error: "You are not authorized to moderate this post.")
      end

      case @action
      when "hide"
        @post.update!(status: "hidden")
      when "unhide"
        @post.update!(status: "published")
      when "enable_wiki"
        @post.update!(wiki: true)
      when "disable_wiki"
        @post.update!(wiki: false)
      else
        return ServiceResult.failure(error: "Unknown moderation action.")
      end

      ServiceResult.success(@post)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
