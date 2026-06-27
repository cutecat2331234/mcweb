# frozen_string_literal: true

require "test_helper"

module Community
  class DailyCheckInTest < ActiveSupport::TestCase
    setup do
      # Fresh user per test; assert balance/row DELTAS scoped to this user so
      # residual rows left by other parallel workers can't make us flaky.
      @user = create_user
      SiteSetting.set("forum.points.daily_check_in", "2")
    end

    def points_balance(user)
      Community::PointAccount.find_by(user: user, currency: "points")&.balance.to_i
    end

    test "requires a user" do
      result = Community::DailyCheckIn.call(user: nil)
      assert result.failure?
      assert_equal "checkin_user_required", result.error
    end

    test "first check-in creates a row with streak 1 and awards base points" do
      assert_equal 0, points_balance(@user)

      result = Community::DailyCheckIn.call(user: @user, today: Date.new(2026, 6, 1))
      assert result.success?, "expected success, got #{result.error}"
      assert_equal false, result.value[:already_checked]
      assert_equal 1, result.value[:streak]
      assert_equal 2, result.value[:points_awarded]
      assert_equal 2, result.value[:base]
      assert_equal 0, result.value[:bonus]

      check_in = Community::CheckIn.find_by(user: @user, checked_on: Date.new(2026, 6, 1))
      assert_not_nil check_in
      assert_equal 1, check_in.streak
      assert_equal 2, check_in.points_awarded
      assert_equal 2, points_balance(@user), "balance should increase by base (2)"
    end

    test "second call on the same day is a no-op (already_checked, no extra points, no new row)" do
      day = Date.new(2026, 6, 1)
      Community::DailyCheckIn.call(user: @user, today: day)
      balance_after_first = points_balance(@user)
      rows_after_first = Community::CheckIn.where(user: @user).count

      result = Community::DailyCheckIn.call(user: @user, today: day)
      assert result.success?
      assert_equal true, result.value[:already_checked]
      assert_equal 0, result.value[:points_awarded]
      assert_equal 1, result.value[:streak]

      assert_equal balance_after_first, points_balance(@user), "no extra points on same-day repeat"
      assert_equal rows_after_first, Community::CheckIn.where(user: @user).count, "no new row on same-day repeat"
    end

    test "consecutive days increment the streak 1 -> 2 -> 3" do
      d1 = Date.new(2026, 6, 1)
      r1 = Community::DailyCheckIn.call(user: @user, today: d1)
      r2 = Community::DailyCheckIn.call(user: @user, today: d1 + 1)
      r3 = Community::DailyCheckIn.call(user: @user, today: d1 + 2)

      assert_equal 1, r1.value[:streak]
      assert_equal 2, r2.value[:streak]
      assert_equal 3, r3.value[:streak]
      # base 2 each day, 3 days = 6
      assert_equal 6, points_balance(@user)
    end

    test "a gap resets the streak back to 1" do
      d1 = Date.new(2026, 6, 1)
      Community::DailyCheckIn.call(user: @user, today: d1)
      Community::DailyCheckIn.call(user: @user, today: d1 + 1)
      # Skip d1 + 2; check in on d1 + 3 -> streak resets.
      r = Community::DailyCheckIn.call(user: @user, today: d1 + 3)

      assert_equal 1, r.value[:streak], "streak must reset to 1 after a missed day"
    end

    test "milestone bonus at streak 7: awarded points = base + 5" do
      start = Date.new(2026, 6, 1)
      result = nil
      7.times { |i| result = Community::DailyCheckIn.call(user: @user, today: start + i) }

      assert_equal 7, result.value[:streak]
      assert_equal 2, result.value[:base]
      assert_equal 5, result.value[:bonus]
      assert_equal 7, result.value[:points_awarded], "base 2 + milestone bonus 5"

      day7 = Community::CheckIn.find_by(user: @user, checked_on: start + 6)
      assert_equal 7, day7.points_awarded, "row records base + bonus on the milestone day"

      # Total balance: 6 normal days * 2 = 12, plus day 7 = 7 -> 19.
      assert_equal 19, points_balance(@user)
    end

    test "milestone bonus only fires on the exact milestone day" do
      start = Date.new(2026, 6, 1)
      result = nil
      8.times { |i| result = Community::DailyCheckIn.call(user: @user, today: start + i) }

      # Day 8: past the milestone, bonus resets to 0.
      assert_equal 8, result.value[:streak]
      assert_equal 0, result.value[:bonus]
      assert_equal 2, result.value[:points_awarded]
    end

    test "base 0 (feature disabled) still records the check-in row but awards nothing" do
      SiteSetting.set("forum.points.daily_check_in", "0")
      result = Community::DailyCheckIn.call(user: @user, today: Date.new(2026, 6, 1))

      assert result.success?
      assert_equal 0, result.value[:points_awarded]
      assert_equal 1, result.value[:streak]
      assert_not_nil Community::CheckIn.find_by(user: @user, checked_on: Date.new(2026, 6, 1))
      assert_equal 0, points_balance(@user), "disabled feature awards no points"
    end

    test "dedupe_token prevents a double award even via a direct AwardPoints call with the same token" do
      day = Date.new(2026, 6, 1)
      Community::DailyCheckIn.call(user: @user, today: day)
      assert_equal 2, points_balance(@user)

      # Replaying the exact token AwardPoints used must be deduped (no extra points).
      token = "checkin:#{@user.id}:#{day.iso8601}"
      replay = Community::AwardPoints.call(user: @user, amount: 2, reason: "daily_check_in", dedupe_token: token)
      assert replay.success?
      assert_equal true, replay.value[:duplicate]
      assert_equal 2, points_balance(@user), "token dedupe blocks the replay"
    end

    test "exactly one transaction is recorded per check-in day" do
      day = Date.new(2026, 6, 1)
      Community::DailyCheckIn.call(user: @user, today: day)
      Community::DailyCheckIn.call(user: @user, today: day) # same-day no-op

      account = Community::PointAccount.find_by(user: @user, currency: "points")
      token = "checkin:#{@user.id}:#{day.iso8601}"
      assert_equal 1, account.transactions.where(dedupe_token: token).count
    end
  end
end
