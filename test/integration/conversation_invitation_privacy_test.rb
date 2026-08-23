# frozen_string_literal: true

require "test_helper"

class ConversationInvitationPrivacyTest < ActionDispatch::IntegrationTest
  setup do
    @creator = create_user(username: "invitewebcreator#{SecureRandom.hex(3)}")
    @invitee = create_user(username: "invitewebuser#{SecureRandom.hex(3)}")
    @outsider = create_user(username: "invitewebother#{SecureRandom.hex(3)}")
    @existing_member = create_user(username: "invitewebmember#{SecureRandom.hex(3)}")
    [ @creator, @invitee, @outsider, @existing_member ].each { |user| enable_forum_pm!(user) }

    result = Community::CreateGroupConversation.call(
      sender: @creator,
      title: "Invitation-only group",
      recipient_usernames: [ @invitee.username ],
      body: "secret history before acceptance"
    )
    @conversation = result.value[:conversation]
    @invitation = result.value[:invitations].first
    @conversation.participants.create!(user: @existing_member)
  end

  test "pending invite appears separately without granting detail or leaking history" do
    sign_in_as(@invitee)

    get forum_conversation_path(@conversation)
    assert_response :not_found

    get forum_conversations_path
    assert_response :success
    assert_includes response.body, "conversationInvitations"
    assert_includes response.body, "Invitation-only group"
    assert_includes response.body, @creator.username
    assert_not_includes response.body, "secret history before acceptance"
    assert_not_includes response.body, @existing_member.username
    assert_not_includes response.body, forum_conversation_path(@conversation)
    assert_not Community::Conversation.for_user(@invitee).exists?(@conversation.id)
  end

  test "pending invite is absent from the conversation API" do
    _record, token = Administration::ApiKey.generate!(
      name: "pending-invite-#{SecureRandom.hex(3)}",
      scopes: %w[read],
      user: @invitee
    )
    headers = { "Authorization" => "Bearer #{token}" }

    get "/api/v1/conversations", headers: headers
    assert_response :success
    ids = JSON.parse(response.body).fetch("data").map { |row| row.fetch("id") }
    assert_not_includes ids, @conversation.id

    get "/api/v1/conversations/#{@conversation.id}", headers: headers
    assert_response :not_found
  end

  test "accept route grants access only to the owning invitee" do
    sign_in_as(@invitee)

    post accept_forum_conversation_invitation_path(@invitation)

    assert_redirected_to forum_conversation_path(@conversation)
    assert @conversation.participant?(@invitee)
    follow_redirect!
    assert_response :success
    assert_includes response.body, "secret history before acceptance"
  end

  test "decline route does not grant access" do
    sign_in_as(@invitee)

    post decline_forum_conversation_invitation_path(@invitation)

    assert_redirected_to forum_conversations_path
    assert @invitation.reload.declined?
    assert_not @conversation.participant?(@invitee)
  end

  test "another account cannot enumerate or answer an invitation public id" do
    sign_in_as(@outsider)

    post accept_forum_conversation_invitation_path(@invitation)

    assert_response :not_found
    assert @invitation.reload.pending?
    assert_not @conversation.participant?(@outsider)
  end
end
