# frozen_string_literal: true

require "test_helper"

class NotificationDndTest < ActionDispatch::IntegrationTest
  test "do_not_disturb? reflects the DND window" do
    user = create_user
    assert_not Community::InstantEmailDelivery.do_not_disturb?(user)

    user.update!(forum_dnd_until: 1.hour.from_now)
    assert Community::InstantEmailDelivery.do_not_disturb?(user)

    user.update!(forum_dnd_until: 1.hour.ago)
    assert_not Community::InstantEmailDelivery.do_not_disturb?(user)
  end

  test "instant email is suppressed while DND is active" do
    user = create_user
    user.update!(forum_dnd_until: 1.hour.from_now)
    assert_not Community::InstantEmailDelivery.allowed?(user, notification_type: "forum.private_message")
  end

  test "preferences update sets and clears the DND window" do
    user = create_user
    sign_in_as(user)

    patch forum_preferences_path, params: { dnd_minutes: 60 }
    assert user.reload.forum_dnd_until.present?
    assert user.forum_dnd_until > Time.current

    patch forum_preferences_path, params: { dnd_minutes: 0 }
    assert_nil user.reload.forum_dnd_until
  end
end
