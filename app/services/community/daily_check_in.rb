# frozen_string_literal: true

module Community
  # Records a user's daily check-in, computes the consecutive-day streak and
  # awards points via the existing Community::AwardPoints service.
  #
  #   Community::DailyCheckIn.call(user: current_user)
  #   Community::DailyCheckIn.call(user: u, today: Date.current - 1)  # backfill / tests
  #
  # Points design (anti-farming):
  #   * base  = SiteSetting "forum.points.daily_check_in" (default 2). 0 disables
  #             the reward but a check-in row is still recorded (streak still tracked).
  #   * bonus = a one-off milestone reward granted ONLY on the exact day a streak
  #             milestone is reached: streak 7 -> +5, 14 -> +10, 30 -> +20.
  #             Every other day bonus = 0. This is naturally hard-capped (at most
  #             +20 extra on a single day) and cannot be farmed beyond the milestone
  #             days, since each milestone fires at most once per consecutive run.
  #   total  = base + bonus.
  #
  # Idempotency:
  #   * A unique index on (user_id, checked_on) means at most one row per day.
  #   * AwardPoints is called with dedupe_token "checkin:<user_id>:<iso_date>", and
  #     its partial unique index on dedupe_token guarantees points are awarded once
  #     even under a concurrent double-submit. The CheckIn row and the points award
  #     share a transaction, so they stay consistent (a points failure rolls the
  #     row back; an already-recorded row awards nothing).
  #
  # Returns a ServiceResult. Success values:
  #   already checked today:
  #     { already_checked: true, check_in:, streak:, points_awarded: 0 }
  #   fresh check-in:
  #     { already_checked: false, check_in:, streak:, points_awarded:, base:, bonus:, balance: }
  class DailyCheckIn < ApplicationService
    # streak day => one-off bonus points granted on that exact day.
    MILESTONE_BONUSES = { 7 => 5, 14 => 10, 30 => 20 }.freeze

    def initialize(user:, today: Date.current)
      @user = user
      @today = today
    end

    def call
      return ServiceResult.failure(error: "checkin_user_required") if @user.nil?

      existing = Community::CheckIn.find_by(user: @user, checked_on: @today)
      return already_checked_result(existing) if existing

      streak = compute_streak
      base = base_points
      bonus = MILESTONE_BONUSES.fetch(streak, 0)
      total = base + bonus

      check_in = nil
      balance = nil

      begin
        Community::CheckIn.transaction do
          begin
            check_in = Community::CheckIn.create!(
              user: @user,
              checked_on: @today,
              streak: streak,
              points_awarded: total
            )
          rescue ActiveRecord::RecordNotUnique
            # Concurrent double-submit raced us to the row. Reload it and award
            # nothing (the winning request already handled the points).
            existing = Community::CheckIn.find_by!(user: @user, checked_on: @today)
            return already_checked_result(existing)
          end

          award = Community::AwardPoints.call(
            user: @user,
            amount: total,
            reason: "daily_check_in",
            dedupe_token: "checkin:#{@user.id}:#{@today.iso8601}"
          )

          # skipped (amount 0) and duplicate (token already awarded) are fine and
          # must NOT roll back the check-in row. A genuine failure must.
          raise AwardFailed, award unless award.success?

          balance = award.value[:balance]
        end
      rescue AwardFailed => e
        return ServiceResult.failure(error: e.result.error, errors: e.result.errors)
      end

      ServiceResult.success(
        already_checked: false,
        check_in: check_in,
        streak: streak,
        points_awarded: total,
        base: base,
        bonus: bonus,
        balance: balance
      )
    end

    private

    class AwardFailed < StandardError
      attr_reader :result

      def initialize(result)
        @result = result
        super("award failed")
      end
    end

    def already_checked_result(check_in)
      ServiceResult.success(
        already_checked: true,
        check_in: check_in,
        streak: check_in.streak,
        points_awarded: 0
      )
    end

    def compute_streak
      yesterday = Community::CheckIn.find_by(user: @user, checked_on: @today - 1)
      yesterday ? yesterday.streak + 1 : 1
    end

    def base_points
      SiteSetting.get("forum.points.daily_check_in", "2").to_i
    end
  end
end
