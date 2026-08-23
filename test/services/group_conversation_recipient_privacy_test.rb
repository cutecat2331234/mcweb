# frozen_string_literal: true

require "test_helper"

class GroupConversationRecipientPrivacyTest < ActiveSupport::TestCase
  setup do
    @sender = create_user
    @recipient = create_user
    [ @sender, @recipient ].each { |user| enable_forum_pm!(user) }
  end

  test "initial group creation honors the recipient private-message policy" do
    @recipient.update!(forum_pm_policy: "staff_only")

    assert_no_difference [
      -> { Community::Conversation.count },
      -> { Community::Message.count },
      -> { @recipient.notifications.where(notification_type: "forum.private_message").count }
    ] do
      result = start_group

      assert_predicate result, :failure?
      assert_equal I18n.t("mcweb.services.errors.pm_not_accepted"), result.error
    end
  end

  test "initial group creation allows a sender accepted by following-only policy" do
    @recipient.update!(forum_pm_policy: "following_only")
    Community::UserFollow.create!(follower: @recipient, followed: @sender)

    result = start_group

    assert_predicate result, :success?
    assert_predicate result.value[:conversation], :is_group?
    assert_not result.value[:conversation].participant?(@recipient)
    assert result.value[:conversation].invitations.where(user: @recipient, status: "pending").exists?
  end

  private

  def start_group
    Community::CreateGroupConversation.call(
      sender: @sender,
      title: "Private group",
      recipient_usernames: [ @recipient.username ],
      body: "Sensitive first message"
    )
  end
end
