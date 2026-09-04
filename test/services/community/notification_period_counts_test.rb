# frozen_string_literal: true

require "test_helper"

class NotificationPeriodCountsTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    suffix = SecureRandom.hex(5)
    @user = User.create!(
      email: "notification-counts-#{suffix}@example.com",
      username: "notification_counts_#{suffix}",
      password: "password123"
    )
  end

  test "computes every notification period in one aggregate query" do
    now = Time.zone.local(2026, 7, 26, 12, 0, 0)

    travel_to now do
      create_notification_at(Time.zone.local(2026, 7, 26, 8, 0, 0))
      create_notification_at(Time.zone.local(2026, 7, 21, 8, 0, 0))
      create_notification_at(Time.zone.local(2026, 6, 15, 8, 0, 0))
      create_notification_at(Time.zone.local(2025, 6, 15, 8, 0, 0))

      selects = []
      callback = lambda do |_name, _started, _finished, _unique_id, payload|
        sql = payload[:sql].to_s
        selects << sql if sql.match?(/\ASELECT/i) && sql.include?("notifications")
      end

      counts = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        Community::NotificationPeriodCounts.call(@user.notifications)
      end

      assert_equal 1, counts.fetch("today")
      assert_equal 2, counts.fetch("this_week")
      assert_equal 2, counts.fetch("this_month")
      assert_equal 1, counts.fetch("last_month")
      assert_equal 1, counts.fetch("last_year")
      assert_equal 1, selects.size
      assert_includes selects.first, "FILTER"
      assert_includes selects.first, "$1"
      quoted_today_boundary = Notification.connection.quote(now.beginning_of_day)
      assert_includes(
        selects.first,
        %("notifications"."created_at" >= #{quoted_today_boundary})
      )
    end
  end

  private

  def create_notification_at(created_at)
    Notification.create!(
      user: @user,
      notification_type: "forum.mention",
      title: "Notification",
      created_at: created_at,
      updated_at: created_at
    )
  end
end
