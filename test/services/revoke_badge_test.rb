# frozen_string_literal: true

require "test_helper"

class RevokeBadgeTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @badge = Community::Badge.create!(name: "Helper", slug: "helper-#{SecureRandom.hex(3)}", grant_rule: "manual")
  end

  test "revokes a granted badge" do
    Community::AwardBadge.call(user: @user, badge_slug: @badge.slug)
    assert Community::UserBadge.exists?(user: @user, badge: @badge)

    result = Community::RevokeBadge.call(user: @user, badge_slug: @badge.slug)
    assert result.success?
    assert_not Community::UserBadge.exists?(user: @user, badge: @badge)
  end

  test "is a no-op success when the user does not hold the badge" do
    assert Community::RevokeBadge.call(user: @user, badge_slug: @badge.slug).success?
  end

  test "fails for an unknown badge slug" do
    assert Community::RevokeBadge.call(user: @user, badge_slug: "does-not-exist").failure?
  end
end
