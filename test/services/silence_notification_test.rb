# frozen_string_literal: true

require "test_helper"

class SilenceNotificationTest < ActiveSupport::TestCase
  test "silencing a user notifies them with the reason" do
    mod = create_user
    grant_permission(mod, "forum.users.mute")
    target = create_user

    assert_difference -> { target.notifications.where(notification_type: "forum.silenced").count }, 1 do
      result = Community::CreateMute.call(actor: mod, user: target, reason: "spamming the forum")
      assert result.success?, result.error
    end

    note = target.notifications.where(notification_type: "forum.silenced").last
    assert_includes note.body.to_s, "spamming the forum"
  end
end
