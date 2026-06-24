# frozen_string_literal: true

require "test_helper"

class WarningAutoSuspendTest < ActiveSupport::TestCase
  setup do
    @mod = create_user
    grant_permission(@mod, "forum.users.warn")
    @user = create_user
  end

  test "suspends the user when warning points reach the suspend threshold" do
    SiteSetting.set("forum.warning_suspend_threshold", "10")
    SiteSetting.set("forum.warning_suspend_days", "5")

    Community::CreateUserWarning.call(actor: @mod, user: @user, reason: "severe abuse", points: 10)

    @user.reload
    assert @user.locked_until.present?
    assert @user.locked_until.future?
  end

  test "does not suspend below the threshold" do
    SiteSetting.set("forum.warning_suspend_threshold", "10")
    Community::CreateUserWarning.call(actor: @mod, user: @user, reason: "minor", points: 3)
    assert_nil @user.reload.locked_until
  end
end
