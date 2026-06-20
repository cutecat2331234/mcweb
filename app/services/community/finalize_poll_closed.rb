# frozen_string_literal: true

module Community
  class FinalizePollClosed < ApplicationService
    def initialize(poll:, actor:, body:)
      @poll = poll
      @actor = actor
      @body = body.to_s.strip
    end

    def call
      return ServiceResult.success(skipped: true) if @poll.closes_at.nil?
      return ServiceResult.success(skipped: true) if already_finalized?

      Community::CreateSmallActionPost.call(topic: @poll.topic, actor: @actor, body: @body) if @actor
      Community::NotifyPollClosed.call(poll: @poll, actor: @actor || @poll.topic.user)
      @poll.touch

      ServiceResult.success
    end

    private

    def already_finalized?
      patterns = [ "%关闭了投票%", "%closed the poll%" ]
      @poll.topic.posts.where(post_type: "small_action").exists?(
        [ ([ "body LIKE ?" ] * patterns.size).join(" OR "), *patterns ]
      )
    end
  end
end
