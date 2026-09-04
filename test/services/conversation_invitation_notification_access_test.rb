# frozen_string_literal: true

require "test_helper"

class ConversationInvitationNotificationAccessTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @creator = create_user(username: "notifyinvitecreator#{SecureRandom.hex(3)}")
    @invitee = create_user(username: "notifyinvitee#{SecureRandom.hex(3)}")
    [ @creator, @invitee ].each { |user| enable_forum_pm!(user) }
    @conversation = Community::Conversation.create!(
      creator: @creator,
      is_group: true,
      title: "Notification-safe group"
    )
    @conversation.participants.create!(user: @creator)
    @conversation.messages.create!(user: @creator, body: "mailer must never include this history")
  end

  test "pending invite notification is visible without conversation membership" do
    NotificationPreference.set!(@invitee, channel: "in_app", notification_type: "forum.conversation_invite", enabled: true)
    Community::AddConversationParticipant.call(
      actor: @creator,
      conversation: @conversation,
      username: @invitee.username
    )
    notification = @invitee.notifications.where(notification_type: "forum.conversation_invite").last!

    assert_not @conversation.participant?(@invitee)
    assert Community::NotificationAccess.visible?(notification: notification, user: @invitee)
    assert_equal Rails.application.routes.url_helpers.forum_conversations_path(
      anchor: "conversation-invitations"
    ), notification.destination_path
  end

  test "declined or blocked invite notifications fail closed" do
    NotificationPreference.set!(@invitee, channel: "in_app", notification_type: "forum.conversation_invite", enabled: true)
    Community::AddConversationParticipant.call(
      actor: @creator,
      conversation: @conversation,
      username: @invitee.username
    )
    invitation = Community::ConversationInvitation.find_by!(conversation: @conversation, user: @invitee, status: "pending")
    notification = @invitee.notifications.where(notification_type: "forum.conversation_invite").last!

    Community::DeclineConversationInvitation.call(user: @invitee, invitation: invitation)
    assert_not Community::NotificationAccess.visible?(notification: notification, user: @invitee)
    assert notification.reload.read?

    Community::AddConversationParticipant.call(
      actor: @creator,
      conversation: @conversation,
      username: @invitee.username
    )
    second_notification = @invitee.notifications.where(notification_type: "forum.conversation_invite").last!
    Community::SetUserBlock.call(
      blocker: @invitee,
      blocked_username: @creator.username,
      desired_state: true
    )
    assert_not Community::NotificationAccess.visible?(notification: second_notification, user: @invitee)
    assert second_notification.reload.read?
  end

  test "accepted invitation notification is retired even after membership is granted" do
    NotificationPreference.set!(@invitee, channel: "in_app", notification_type: "forum.conversation_invite", enabled: true)
    Community::AddConversationParticipant.call(
      actor: @creator,
      conversation: @conversation,
      username: @invitee.username
    )
    invitation = Community::ConversationInvitation.find_by!(conversation: @conversation, user: @invitee, status: "pending")
    notification = @invitee.notifications.where(notification_type: "forum.conversation_invite").last!

    assert_predicate Community::AcceptConversationInvitation.call(user: @invitee, invitation: invitation), :success?

    assert @conversation.participant?(@invitee)
    assert_not Community::NotificationAccess.visible?(notification: notification, user: @invitee)
    assert notification.reload.read?
  end

  test "email preference enqueues only the invitation mailer without message history" do
    invitation = @conversation.invitations.create!(
      user: @invitee,
      invited_by: @creator,
      expires_at: 7.days.from_now
    )
    NotificationPreference.set!(@invitee, channel: "in_app", notification_type: "forum.conversation_invite", enabled: false)
    NotificationPreference.set!(@invitee, channel: "email", notification_type: "forum.conversation_invite", enabled: true)

    assert_enqueued_jobs 1, only: MailDeliveryJob do
      Community::NotifyConversationInvitation.call(invitation: invitation)
    end

    email = Community::ForumMailer.conversation_invitation(@invitee.id, invitation.public_id)
    assert_includes email.body.encoded, "Notification-safe group"
    assert_not_includes email.body.encoded, "mailer must never include this history"
  end
end
