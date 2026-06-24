# frozen_string_literal: true

require "test_helper"

class EditMessageTest < ActionDispatch::IntegrationTest
  setup do
    @a = create_user
    @b = create_user
    [ @a, @b ].each { |u| enable_forum_pm!(u) }
    @conversation = Community::CreateConversation.call(sender: @a, recipient_username: @b.username, body: "first").value[:conversation]
    @msg = @conversation.messages.create!(user: @a, body: "original body")
  end

  test "author can edit their own message" do
    sign_in_as(@a)
    patch forum_conversation_message_path(@conversation, @msg), params: { message: { body: "edited body" } }
    assert_redirected_to forum_conversation_path(@conversation)
    @msg.reload
    assert_equal "edited body", @msg.body
    assert @msg.edited?
  end

  test "a participant cannot edit another user's message" do
    sign_in_as(@b)
    patch forum_conversation_message_path(@conversation, @msg), params: { message: { body: "hijacked" } }
    assert_equal "original body", @msg.reload.body
    assert_not @msg.edited?
  end

  test "blank body is rejected" do
    sign_in_as(@a)
    patch forum_conversation_message_path(@conversation, @msg), params: { message: { body: "   " } }
    assert_equal "original body", @msg.reload.body
  end
end
