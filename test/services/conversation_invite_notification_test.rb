# frozen_string_literal: true

require "test_helper"

class ConversationInviteNotificationTest < ActiveSupport::TestCase
  setup do
    @creator = create_user
    @member = create_user
    @invitee = create_user
    [ @creator, @member, @invitee ].each { |u| enable_forum_pm!(u) }
    @conversation = Community::CreateGroupConversation.call(
      sender: @creator,
      title: "Team",
      recipient_usernames: [ @member.username ],
      body: "hello team"
    ).value[:conversation]
  end

  test "notifies a user when they are added to a group conversation" do
    assert_difference -> { Notification.where(user: @invitee, notification_type: "forum.conversation_invite").count }, 1 do
      result = Community::AddConversationParticipant.call(actor: @creator, conversation: @conversation, username: @invitee.username)
      assert result.success?
    end
  end
end
