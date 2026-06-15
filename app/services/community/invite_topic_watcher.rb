# frozen_string_literal: true

module Community
  class InviteTopicWatcher < ApplicationService
    def initialize(inviter:, topic:, username:)
      @inviter = inviter
      @topic = topic
      @username = username.to_s.strip
    end

    def call
      return ServiceResult.failure(error: "请输入用户名。") if @username.blank?
      unless can_invite?
        return ServiceResult.failure(error: "无权邀请用户关注此主题。")
      end

      user = User.find_by("LOWER(username) = ?", @username.downcase)
      return ServiceResult.failure(error: "用户不存在。") unless user
      return ServiceResult.failure(error: "不能邀请自己。") if user.id == @inviter.id
      unless PollParticipation.visible?(topic: @topic, user: user)
        return ServiceResult.failure(error: "该用户无法访问此主题。")
      end

      invite = Community::TopicInvite.find_or_initialize_by(topic: @topic, user: user)
      if invite.persisted?
        return ServiceResult.failure(error: "该用户已被邀请过。")
      end

      invite.invited_by = @inviter
      invite.save!

      Community::Subscription.subscribe!(user, @topic, level: "watching")
      Community::NotifyTopicInvite.call(invite: invite)

      ServiceResult.success(invite)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def can_invite?
      @inviter.permission?("forum.topics.lock") || @inviter.id == @topic.user_id
    end
  end
end
