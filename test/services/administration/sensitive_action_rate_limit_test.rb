# frozen_string_literal: true

require "test_helper"

class Administration::SensitiveActionRateLimitTest < ActiveSupport::TestCase
  setup do
    @user = create_user
  end

  test "failures lock user and IP dimensions within an action scope and success clears them" do
    5.times do
      result = Administration::SensitiveActionRateLimit.call(
        scope: "destructive_action",
        user: @user,
        ip_address: "203.0.113.30",
        action: :failure
      )
      assert_predicate result, :success?
    end

    blocked = Administration::SensitiveActionRateLimit.call(
      scope: "destructive_action",
      user: @user,
      ip_address: "203.0.113.30",
      action: :check
    )
    assert_predicate blocked, :failure?
    assert_equal :rate_limited, blocked.code

    other_scope = Administration::SensitiveActionRateLimit.call(
      scope: "different_action",
      user: @user,
      ip_address: "203.0.113.30",
      action: :check
    )
    assert_predicate other_scope, :success?

    cleared = Administration::SensitiveActionRateLimit.call(
      scope: "destructive_action",
      user: @user,
      ip_address: "203.0.113.30",
      action: :success
    )
    assert_predicate cleared, :success?
    assert_predicate Administration::SensitiveActionRateLimit.call(
      scope: "destructive_action",
      user: @user,
      ip_address: "203.0.113.30",
      action: :check
    ), :success?
  end
end
