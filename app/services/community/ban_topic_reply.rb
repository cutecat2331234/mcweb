# frozen_string_literal: true

module Community
  class BanTopicReply < ApplicationService
    def initialize(actor:, topic:, user:, reason: nil, expires_at: nil)
      @actor = actor
      @topic = topic
      @user = user
      @reason = reason.to_s.strip.presence
      @expires_at = expires_at
    end

    def call
      unless @actor.permission?("forum.topics.lock")
        return ServiceResult.failure(error: "无权禁止用户回复。")
      end

      ban = Community::TopicReplyBan.find_or_initialize_by(topic: @topic, user: @user)
      ban.assign_attributes(created_by: @actor, reason: @reason, expires_at: @expires_at)
      ban.save!

      ServiceResult.success(ban)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
