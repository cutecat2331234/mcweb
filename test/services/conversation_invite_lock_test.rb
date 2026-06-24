# frozen_string_literal: true

require "test_helper"

class ConversationInviteLockTest < ActiveSupport::TestCase
  setup do
    @creator = create_user
    @member = create_user
    @newcomer = create_user
    [ @creator, @member, @newcomer ].each { |u| enable_forum_pm!(u) }

    @conversation = Community::Conversation.create!(creator: @creator, is_group: true)
    @conversation.participants.create!(user: @creator)
    @conversation.participants.create!(user: @member)
  end

  test "any participant can add a member when invites are unlocked" do
    @conversation.update!(invites_locked: false)
    result = Community::AddConversationParticipant.call(actor: @member, conversation: @conversation, username: @newcomer.username)
    assert result.success?, result.error
    assert @conversation.participant?(@newcomer)
  end

  test "only the creator can add a member when invites are locked" do
    @conversation.update!(invites_locked: true)

    blocked = Community::AddConversationParticipant.call(actor: @member, conversation: @conversation, username: @newcomer.username)
    assert blocked.failure?
    assert_not @conversation.participant?(@newcomer)

    allowed = Community::AddConversationParticipant.call(actor: @creator, conversation: @conversation, username: @newcomer.username)
    assert allowed.success?, allowed.error
    assert @conversation.participant?(@newcomer)
  end
end
