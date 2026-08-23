# frozen_string_literal: true

require "test_helper"

class ConversationInvitationLifecycleTest < ActiveSupport::TestCase
  setup do
    @creator = create_user(username: "invitecreator#{SecureRandom.hex(3)}")
    @member = create_user(username: "invitemember#{SecureRandom.hex(3)}")
    @invitee = create_user(username: "invitee#{SecureRandom.hex(3)}")
    [ @creator, @member, @invitee ].each { |user| enable_forum_pm!(user) }

    @conversation = Community::Conversation.create!(
      creator: @creator,
      is_group: true,
      title: "Private planning",
      last_message_at: Time.current
    )
    @conversation.participants.create!(user: @creator)
    @conversation.participants.create!(user: @member)
    @conversation.messages.create!(user: @creator, body: "history before consent")
  end

  test "normal add creates one pending invitation without membership or inbox access" do
    assert_difference -> { Community::ConversationInvitation.count }, 1 do
      assert_no_difference -> { @conversation.participants.count } do
        result = invite(@invitee)
        assert_predicate result, :success?
      end
    end

    invitation = pending_invitation(@invitee)
    assert invitation.pending?
    assert_not @conversation.participant?(@invitee)
    assert_not Community::Conversation.for_user(@invitee, include_archived: true).exists?(@conversation.id)
  end

  test "duplicate add is idempotent and does not duplicate the pending invitation" do
    invite(@invitee)

    assert_no_difference [
      -> { Community::ConversationInvitation.where(user: @invitee, conversation: @conversation).count },
      -> { Notification.where(user: @invitee, notification_type: "forum.conversation_invite").count }
    ] do
      assert_predicate invite(@invitee), :success?
    end
  end

  test "accept atomically creates membership and repeated accept converges" do
    invite(@invitee)
    invitation = pending_invitation(@invitee)

    assert_difference -> { @conversation.participants.where(user: @invitee).count }, 1 do
      result = Community::AcceptConversationInvitation.call(user: @invitee, invitation: invitation)
      assert_predicate result, :success?
      assert_equal @conversation.id, result.value.id
    end

    assert invitation.reload.accepted?
    assert Community::Conversation.for_user(@invitee).exists?(@conversation.id)
    assert_no_difference -> { @conversation.participants.where(user: @invitee).count } do
      assert_predicate Community::AcceptConversationInvitation.call(user: @invitee, invitation: invitation), :success?
    end
  end

  test "decline is terminal for an attempt and never creates membership" do
    invite(@invitee)
    invitation = pending_invitation(@invitee)

    assert_no_difference -> { @conversation.participants.count } do
      assert_predicate Community::DeclineConversationInvitation.call(user: @invitee, invitation: invitation), :success?
      assert_predicate Community::DeclineConversationInvitation.call(user: @invitee, invitation: invitation), :success?
    end

    assert invitation.reload.declined?
    assert_predicate Community::AcceptConversationInvitation.call(user: @invitee, invitation: invitation), :failure?
    assert_not @conversation.participant?(@invitee)
  end

  test "expired invitation fails closed and becomes terminal" do
    invite(@invitee)
    invitation = pending_invitation(@invitee)
    invitation.update!(expires_at: 1.minute.ago)

    result = Community::AcceptConversationInvitation.call(user: @invitee, invitation: invitation)

    assert_predicate result, :failure?
    assert invitation.reload.expired?
    assert_not @conversation.participant?(@invitee)
  end

  test "expiry job closes stale pending invitations without creating membership" do
    invite(@invitee)
    invitation = pending_invitation(@invitee)
    invitation.update!(expires_at: 1.minute.ago)

    Community::ExpireConversationInvitationsJob.perform_now

    assert invitation.reload.expired?
    assert_not @conversation.participant?(@invitee)
  end

  test "blocking any current participant revokes a pending invitation" do
    invite(@invitee)
    invitation = pending_invitation(@invitee)

    result = Community::SetUserBlock.call(
      blocker: @invitee,
      blocked_username: @member.username,
      desired_state: true
    )

    assert_predicate result, :success?
    assert invitation.reload.revoked?
    assert_predicate Community::AcceptConversationInvitation.call(user: @invitee, invitation: invitation), :failure?
    assert_not @conversation.participant?(@invitee)
  end

  test "pending invitations reserve configured participant capacity" do
    previous = SiteSetting.get("forum.group_pm_max_participants")
    SiteSetting.set("forum.group_pm_max_participants", "3")
    second_invitee = create_user(username: "inviteesecond#{SecureRandom.hex(3)}")
    enable_forum_pm!(second_invitee)

    assert_predicate invite(@invitee), :success?
    result = invite(second_invitee)

    assert_predicate result, :failure?
    assert_not Community::ConversationInvitation.where(user: second_invitee, status: "pending").exists?
  ensure
    SiteSetting.set("forum.group_pm_max_participants", previous || "10")
  end

  test "only explicit staff or system service calls can bypass consent" do
    ordinary_target = @invitee
    blocked = Community::AddConversationParticipant.call(
      actor: @creator,
      conversation: @conversation,
      username: ordinary_target.username,
      direct_membership: true
    )
    assert_predicate blocked, :failure?
    assert_not @conversation.participant?(ordinary_target)

    staff = create_user(username: "invitestaff#{SecureRandom.hex(3)}")
    staff_target = create_user(username: "stafftarget#{SecureRandom.hex(3)}")
    enable_forum_pm!(staff_target)
    grant_permission(staff, "forum.topics.lock")
    allowed = Community::AddConversationParticipant.call(
      actor: staff,
      conversation: @conversation,
      username: staff_target.username,
      direct_membership: true
    )
    assert_predicate allowed, :success?
    assert @conversation.participant?(staff_target)

    system_target = create_user(username: "systemtarget#{SecureRandom.hex(3)}")
    enable_forum_pm!(system_target)
    system = Community::AddConversationParticipant.call(
      actor: nil,
      conversation: @conversation,
      username: system_target.username,
      direct_membership: true,
      system_operation: true
    )
    assert_predicate system, :success?
    assert @conversation.participant?(system_target)
  end

  test "explicit direct membership consumes the target's reserved invitation slot" do
    NotificationPreference.set!(
      @invitee,
      channel: "in_app",
      notification_type: "forum.conversation_invite",
      enabled: true
    )
    assert_predicate invite(@invitee), :success?
    invitation = pending_invitation(@invitee)
    notification = @invitee.notifications.where(notification_type: "forum.conversation_invite").last!

    staff = create_user(username: "inviteoverride#{SecureRandom.hex(3)}")
    grant_permission(staff, "forum.topics.lock")
    result = Community::AddConversationParticipant.call(
      actor: staff,
      conversation: @conversation,
      username: @invitee.username,
      direct_membership: true
    )

    assert_predicate result, :success?
    assert @conversation.participant?(@invitee)
    assert invitation.reload.accepted?
    assert notification.reload.read?
  end

  private

  def invite(user)
    Community::AddConversationParticipant.call(
      actor: @creator,
      conversation: @conversation,
      username: user.username
    )
  end

  def pending_invitation(user)
    Community::ConversationInvitation.find_by!(
      conversation: @conversation,
      user: user,
      status: "pending"
    )
  end
end
