# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

class MembersOnlineCountTest < ActionDispatch::IntegrationTest
  test "members page keeps the recently-seen aggregate private" do
    online = create_user
    online.update_column(:last_seen_at, 1.minute.ago)
    offline = create_user
    offline.update_column(:last_seen_at, 2.hours.ago)

    get forum_members_path
    assert_response :success
    assert_nil inertia.props.deep_symbolize_keys[:onlineCount]

    staff = create_user
    grant_permission(staff, Community::UserProfileVisibility::PRIVATE_ACTIVITY_PERMISSION)
    sign_in_as(staff)
    get forum_members_path
    assert_response :success

    count = inertia.props.deep_symbolize_keys[:onlineCount]
    assert_operator count, :>=, 1
    refute_includes [ nil ], count
  end
end
