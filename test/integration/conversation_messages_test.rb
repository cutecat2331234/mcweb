# frozen_string_literal: true

require "test_helper"

class ConversationMessagesTest < ActionDispatch::IntegrationTest
  setup do
    @alice = create_user
    @bob = create_user
    enable_forum_pm!(@alice)
    enable_forum_pm!(@bob)
    sign_in_as(@alice)
    result = Community::CreateConversation.call(
      sender: @alice,
      recipient_username: @bob.username,
      body: "Hello"
    )
    @conversation = result.value[:conversation]
  end

  test "empty message returns validation errors in props" do
    post forum_conversation_messages_path(@conversation), params: { message: { body: "" } }

    assert_response :unprocessable_entity
    assert_includes response.body, "form_errors"
    assert_includes response.body, "消息内容不能为空"
  end
end
