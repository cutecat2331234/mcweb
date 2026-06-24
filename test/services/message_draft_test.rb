# frozen_string_literal: true

require "test_helper"

class MessageDraftTest < ActionDispatch::IntegrationTest
  setup do
    @a = create_user
    @b = create_user
    [ @a, @b ].each { |u| enable_forum_pm!(u) }
    @conversation = Community::CreateConversation.call(sender: @a, recipient_username: @b.username, body: "hi").value[:conversation]
    sign_in_as(@a)
  end

  test "saves a conversation draft and clears it when blank" do
    patch forum_conversation_message_draft_path(@conversation), params: { body: "draft in progress" }
    assert_response :no_content
    assert_equal "draft in progress", Community::MessageDraft.find_by(user: @a, conversation: @conversation)&.body

    patch forum_conversation_message_draft_path(@conversation), params: { body: "   " }
    assert_response :no_content
    assert_nil Community::MessageDraft.find_by(user: @a, conversation: @conversation)
  end

  test "destroy removes the draft" do
    Community::MessageDraft.create!(user: @a, conversation: @conversation, body: "x")
    delete forum_conversation_message_draft_path(@conversation)
    assert_response :no_content
    assert_nil Community::MessageDraft.find_by(user: @a, conversation: @conversation)
  end
end
