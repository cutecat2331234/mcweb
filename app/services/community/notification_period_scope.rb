# frozen_string_literal: true

module Community
  module NotificationPeriodScope
    module_function

    def call(scope, period)
      range = range_for(period)
      range ? scope.where(created_at: range) : scope
    end

    def range_for(period, now: Time.zone.now)
      case period.to_s
      when "today"
        now.beginning_of_day..
      when "this_week"
        now.beginning_of_week..
      when "this_month"
        now.beginning_of_month..
      when "last_month"
        start = now.beginning_of_month.prev_month
        start...now.beginning_of_month
      when "last_year"
        start = now.beginning_of_year.prev_year
        start...now.beginning_of_year
      end
    end
  end
end
