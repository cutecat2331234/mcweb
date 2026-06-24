# frozen_string_literal: true

require "test_helper"

class ConfigurablePmLimitsTest < ActiveSupport::TestCase
  test "group_pm_max_participants caps the recipient count" do
    creator = create_user
    member = create_user
    newcomer = create_user
    [ creator, member, newcomer ].each { |u| enable_forum_pm!(u) }
    SiteSetting.set("forum.group_pm_max_participants", "2")

    conv = Community::Conversation.create!(creator: creator, is_group: true)
    conv.participants.create!(user: creator)
    conv.participants.create!(user: member) # at the cap of 2

    result = Community::AddConversationParticipant.call(actor: creator, conversation: conv, username: newcomer.username)
    assert result.failure?
    assert_equal 2, conv.participants.count
    assert_not conv.participant?(newcomer)
  end

  test "min_trust_level_pm gates who can start a private message" do
    user = create_user # trust level 0 (no posts)

    SiteSetting.set("forum.min_trust_level_pm", "2")
    assert_not Community::TrustLevel.can_send_pm?(user)

    SiteSetting.set("forum.min_trust_level_pm", "0")
    assert Community::TrustLevel.can_send_pm?(user)
  end
end
