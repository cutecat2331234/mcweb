# frozen_string_literal: true

module Community
  class InviteTopicWatcher < ApplicationService
    def initialize(inviter:, topic:, username:)
      @inviter = inviter
      @topic = topic
      @username = username.to_s.strip
    end

    def call
      return ServiceResult.failure(error: "invite_username_required") if @username.blank?
      unless can_invite?
        return ServiceResult.failure(error: "invite_watcher_unauthorized")
      end

      user = User.find_by("LOWER(username) = ?", @username.downcase)
      return ServiceResult.failure(error: "user_not_found") unless user
      return ServiceResult.failure(error: "invite_cannot_self") if user.id == @inviter.id
      unless PollParticipation.visible?(topic: @topic, user: user)
        return ServiceResult.failure(error: "invite_user_cannot_access")
      end

      invite = Community::TopicInvite.find_or_initialize_by(topic: @topic, user: user)
      if invite.persisted?
        return ServiceResult.failure(error: "invite_already_sent")
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
