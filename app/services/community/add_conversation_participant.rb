# frozen_string_literal: true

module Community
  class AddConversationParticipant < ApplicationService
    MAX_PARTICIPANTS = 10

    def self.max_participants
      [ SiteSetting.get("forum.group_pm_max_participants", MAX_PARTICIPANTS.to_s).to_i, 1 ].max
    end

    def initialize(actor:, conversation:, username:)
      @actor = actor
      @conversation = conversation
      @username = username.to_s.strip
    end

    def call
      return ServiceResult.failure(error: :not_group_conversation) unless @conversation.is_group?
      return ServiceResult.failure(error: :only_participants_can_add) unless @conversation.participant?(@actor)
      return ServiceResult.failure(error: :group_full) if @conversation.participants.count >= self.class.max_participants
      return ServiceResult.failure(error: :only_creator_can_add) unless can_add_member?(@actor)

      user = User.find_by(username: @username)
      return ServiceResult.failure(error: :user_not_found) unless user
      return ServiceResult.failure(error: :user_already_participant) if @conversation.participant?(user)
      return ServiceResult.failure(error: :cannot_add_self) if user.id == @actor.id
      return ServiceResult.failure(error: :cannot_message_blocked_user) if Community::UserBlock.blocked?(@actor, user)
      return ServiceResult.failure(error: :user_silenced) if Community::UserSilence.silenced?(user)
      return ServiceResult.failure(error: :user_cannot_pm) unless Community::TrustLevel.can_send_pm?(user)
      return ServiceResult.failure(error: "pm_not_accepted") unless Community::PmPolicy.accepts?(recipient: user, sender: @actor)

      pm_restriction = Community::CheckWarningRestrictions.call(user: user, action: :pm)
      return pm_restriction if pm_restriction.failure?

      @conversation.participants.create!(user: user)
      notify_added!(user)
      ServiceResult.success(@conversation)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    def notify_added!(user)
      return unless NotificationPreference.enabled?(user, channel: "in_app", notification_type: "forum.conversation_invite")

      Community::InAppNotification.notify(
        user: user,
        notification_type: "forum.conversation_invite",
        key: "added_to_conversation",
        adder: @actor.username,
        metadata: { conversation_id: @conversation.id }
      )
    end

    def self.can_add_member?(actor, conversation)
      return true unless conversation.is_group?

      creator_only = conversation.invites_locked? ||
        SiteSetting.get("forum.group_pm_creator_only_add", "false") == "true"
      return true unless creator_only

      staff = actor.permission?("forum.topics.lock")
      staff || actor.id == conversation.creator_id
    end

    private

    def can_add_member?(actor)
      self.class.can_add_member?(actor, @conversation)
    end
  end
end
