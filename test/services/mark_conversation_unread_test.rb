# frozen_string_literal: true

require "test_helper"

class MarkConversationUnreadTest < ActionDispatch::IntegrationTest
  setup do
    @a = create_user
    @b = create_user
    [ @a, @b ].each { |u| enable_forum_pm!(u) }
    @conversation = Community::CreateConversation.call(sender: @a, recipient_username: @b.username, body: "hi").value[:conversation]
  end

  test "marks a read conversation as unread for the current user" do
    sign_in_as(@b)
    @conversation.mark_read_for!(@b)
    participant = @conversation.participants.find_by(user: @b)
    assert participant.reload.last_read_at.present?

    post mark_unread_forum_conversation_path(@conversation)
    assert_redirected_to forum_conversations_path
    assert_nil participant.reload.last_read_at
  end
end
