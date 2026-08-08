# frozen_string_literal: true

require "test_helper"

class PerformanceCacheTest < ActiveSupport::TestCase
  test "session activity writes at most once inside the activity window" do
    session = Session.create!(user: create_user)
    base = Time.current.change(usec: 0)
    session.update_column(:last_active_at, base)
    session.reload

    assert_not session.touch_activity!(at: base + 30.seconds)
    assert_equal base, session.reload.last_active_at

    later = base + Session::ACTIVITY_TOUCH_INTERVAL + 1.second
    assert session.touch_activity!(at: later)
    assert_not session.has_changes_to_save?
    assert_equal later, session.reload.last_active_at
  end

  test "effective permissions are reused and invalidated by permission version" do
    user = create_user
    grant_permission(user, "forum.performance.first")
    user.reload

    assert user.permission?("forum.performance.first")
    first_set = user.authorization_permission_keys
    assert_same first_set, user.authorization_permission_keys

    previous_version = user.permission_version
    grant_permission(user, "forum.performance.second")
    user.reload

    assert_operator user.permission_version, :>, previous_version
    assert user.permission?("forum.performance.second")
    assert_not_same first_set, user.authorization_permission_keys
  end

  test "site setting reads cache values and invalidates exact keys" do
    key = "performance.cache.#{SecureRandom.hex(4)}"

    assert_equal "fallback", SiteSetting.get(key, "fallback")
    SiteSetting.set(key, "first")
    assert_equal "first", SiteSetting.get(key)

    SiteSetting.set(key, "second")
    assert_equal "second", SiteSetting.get(key)

    SiteSetting.unset(key)
    assert_equal "fallback", SiteSetting.get(key, "fallback")
  end

  test "frontend navigation cache changes after a nav item mutation" do
    item = Website::NavItem.create!(
      label: "Performance",
      location: "header",
      url: "/performance",
      position: 1,
      visible: true
    )

    assert_includes Website::NavItem.frontend_items("header"),
      { label: "Performance", href: "/performance" }

    item.update!(label: "Fast performance")
    items = Website::NavItem.frontend_items("header")
    assert_includes items, { label: "Fast performance", href: "/performance" }
    assert_not_includes items, { label: "Performance", href: "/performance" }
  ensure
    item&.destroy!
  end
end
