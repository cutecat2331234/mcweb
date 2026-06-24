# frozen_string_literal: true

require "test_helper"

class DeleteMessageTest < ActionDispatch::IntegrationTest
  setup do
    @a = create_user
    @b = create_user
    [ @a, @b ].each { |u| enable_forum_pm!(u) }
    @conversation = Community::CreateConversation.call(sender: @a, recipient_username: @b.username, body: "first").value[:conversation]
    @msg = @conversation.messages.create!(user: @a, body: "a message to delete")
  end

  test "author can delete their own message" do
    sign_in_as(@a)
    delete forum_conversation_message_path(@conversation, @msg)
    assert_redirected_to forum_conversation_path(@conversation)
    assert_not Community::Message.exists?(@msg.id), "soft-deleted message should be excluded by the default scope"
  end

  test "a participant cannot delete another user's message" do
    sign_in_as(@b)
    delete forum_conversation_message_path(@conversation, @msg)
    assert_response :forbidden
    assert Community::Message.exists?(@msg.id)
  end
end
