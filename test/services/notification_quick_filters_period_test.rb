# frozen_string_literal: true

require "test_helper"

class NotificationQuickFiltersPeriodTest < ActiveSupport::TestCase
  test "quick filters respect period filter" do
    user = create_user
    Notification.create!(
      user: user,
      notification_type: "forum.mention",
      title: "Recent",
      body: "b",
      created_at: Time.zone.now.beginning_of_month.prev_month + 2.days
    )
    Notification.create!(
      user: user,
      notification_type: "forum.reaction",
      title: "Ancient",
      body: "b",
      created_at: 2.years.ago
    )

    filters = Community::NotificationQuickFilters.call(
      user: user,
      period: "last_month"
    )

    assert_equal 1, filters.size
    assert_equal "forum.mention", filters.first[:type]
  end
end
