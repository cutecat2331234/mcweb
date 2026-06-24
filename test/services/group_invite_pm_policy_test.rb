# frozen_string_literal: true

require "test_helper"

class GroupInvitePmPolicyTest < ActiveSupport::TestCase
  setup do
    @creator = create_user
    @member = create_user
    @invitee = create_user
    [ @creator, @member, @invitee ].each { |u| enable_forum_pm!(u) }
    @conversation = Community::CreateGroupConversation.call(
      sender: @creator, title: "Team", recipient_usernames: [ @member.username ], body: "hello"
    ).value[:conversation]
  end

  test "respects the invitee's everyone policy" do
    @invitee.update!(forum_pm_policy: "everyone")
    assert Community::AddConversationParticipant.call(actor: @creator, conversation: @conversation, username: @invitee.username).success?
  end

  test "blocks adding someone whose policy is staff_only when the adder is not staff" do
    @invitee.update!(forum_pm_policy: "staff_only")
    result = Community::AddConversationParticipant.call(actor: @creator, conversation: @conversation, username: @invitee.username)
    assert result.failure?
    assert_not @conversation.participant?(@invitee)
  end

  test "staff can add a staff_only user" do
    @invitee.update!(forum_pm_policy: "staff_only")
    grant_permission(@creator, "forum.topics.lock")
    assert Community::AddConversationParticipant.call(actor: @creator, conversation: @conversation, username: @invitee.username).success?
  end
end
