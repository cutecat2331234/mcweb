# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class ConversationLabelTest < ActionDispatch::IntegrationTest
  setup do
    @a = create_user
    @b = create_user
    @c = create_user
    [ @a, @b, @c ].each { |u| enable_forum_pm!(u) }
    @conv1 = Community::CreateConversation.call(sender: @a, recipient_username: @b.username, body: "hi b").value[:conversation]
    @conv2 = Community::CreateConversation.call(sender: @a, recipient_username: @c.username, body: "hi c").value[:conversation]
    sign_in_as(@a)
  end

  test "sets a label only on the current user's participant" do
    post set_label_forum_conversation_path(@conv1), params: { label: "Work" }
    assert_redirected_to forum_conversation_path(@conv1)
    assert_equal "Work", @conv1.participants.find_by(user: @a).reload.label
    assert_nil @conv1.participants.find_by(user: @b).reload.label
  end

  test "filters the inbox by label" do
    @conv1.participants.find_by(user: @a).update!(label: "Work")
    get forum_conversations_path(label: "Work")
    assert_response :success

    ids = inertia.props.deep_symbolize_keys[:conversations].map { |c| c[:id] }
    assert_includes ids, @conv1.id
    assert_not_includes ids, @conv2.id
  end
end
