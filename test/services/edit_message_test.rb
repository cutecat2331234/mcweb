# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class EditMessageTest < ActionDispatch::IntegrationTest
  include InertiaRails::Minitest

  setup do
    @a = create_user
    @b = create_user
    [ @a, @b ].each { |u| enable_forum_pm!(u) }
    @conversation = Community::CreateConversation.call(sender: @a, recipient_username: @b.username, body: "first").value[:conversation]
    @msg = @conversation.messages.create!(user: @a, body: "original body")
  end

  test "author can edit their own message" do
    sign_in_as(@a)
    edit_token = "message-edit-#{SecureRandom.hex(8)}"
    patch forum_conversation_message_path(@conversation, @msg), params: {
      message: { body: "edited body", expected_revision: 1, edit_token: edit_token }
    }
    assert_redirected_to forum_conversation_path(@conversation)
    @msg.reload
    assert_equal "edited body", @msg.body
    assert @msg.edited?
    follow_redirect!
    assert_equal edit_token,
      inertia.props.deep_symbolize_keys.dig(:flash, :message_edit_succeeded)
  end

  test "a participant cannot edit another user's message" do
    sign_in_as(@b)
    patch forum_conversation_message_path(@conversation, @msg), params: {
      message: { body: "hijacked", expected_revision: 1 }
    }
    assert_equal "original body", @msg.reload.body
    assert_not @msg.edited?
  end

  test "blank body is rejected" do
    sign_in_as(@a)
    patch forum_conversation_message_path(@conversation, @msg), params: {
      message: { body: "   ", expected_revision: 1 }
    }
    assert_equal "original body", @msg.reload.body
  end

  test "a missing or non-positive revision cannot bypass optimistic locking" do
    sign_in_as(@a)

    [ nil, 0, -1, "invalid" ].each do |revision|
      patch forum_conversation_message_path(@conversation, @msg), params: {
        message: {
          body: "must not be written",
          expected_revision: revision,
          edit_token: "missing-revision-#{SecureRandom.hex(4)}"
        }
      }

      assert_redirected_to forum_conversation_path(@conversation)
      assert_equal "original body", @msg.reload.body
      assert_equal 1, @msg.revision
    end
  end

  test "a stale edit does not emit the explicit success token" do
    first = Community::EditMessage.call(
      user: @a,
      message: @msg,
      body: "newer body",
      expected_revision: 1
    )
    assert_predicate first, :success?, first.error
    sign_in_as(@a)
    edit_token = "stale-edit-#{SecureRandom.hex(8)}"

    patch forum_conversation_message_path(@conversation, @msg), params: {
      message: { body: "stale body", expected_revision: 1, edit_token: edit_token }
    }

    assert_redirected_to forum_conversation_path(@conversation)
    follow_redirect!
    props = inertia.props.deep_symbolize_keys
    assert_nil props.dig(:flash, :message_edit_succeeded)
    assert_equal I18n.t("mcweb.services.errors.message_revision_conflict"), props.dig(:flash, :alert)
    assert_equal "newer body", @msg.reload.body
  end

  test "a soft-deleted message cannot be edited or republished" do
    @msg.soft_delete!

    result = Community::EditMessage.call(
      user: @a,
      message: @msg,
      body: "resurrected body",
      expected_revision: 1
    )

    assert result.failure?
    assert_equal "message_deleted", result.error
    assert_equal "original body", @msg.reload.body
    assert @msg.deleted?
  end
end
