# frozen_string_literal: true

require "test_helper"

class PmPolicyTest < ActiveSupport::TestCase
  setup do
    @sender = create_user
    @recipient = create_user
    [ @sender, @recipient ].each { |u| enable_forum_pm!(u) }
  end

  def start_pm
    Community::CreateConversation.call(sender: @sender, recipient_username: @recipient.username, body: "hello there")
  end

  test "everyone policy accepts messages" do
    @recipient.update!(forum_pm_policy: "everyone")
    assert start_pm.success?
  end

  test "staff_only rejects non-staff senders" do
    @recipient.update!(forum_pm_policy: "staff_only")
    assert start_pm.failure?
  end

  test "staff_only allows staff senders" do
    @recipient.update!(forum_pm_policy: "staff_only")
    grant_permission(@sender, "forum.topics.lock")
    assert start_pm.success?
  end

  test "following_only accepts senders the recipient follows" do
    @recipient.update!(forum_pm_policy: "following_only")
    Community::UserFollow.create!(follower: @recipient, followed: @sender)
    assert start_pm.success?
  end

  test "following_only rejects senders the recipient does not follow" do
    @recipient.update!(forum_pm_policy: "following_only")
    assert start_pm.failure?
  end
end
