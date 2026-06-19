# frozen_string_literal: true

module Community
  module NotificationPeriodScope
    module_function

    def call(scope, period)
      return scope if period.blank?

      case period.to_s
      when "today"
        scope.where("created_at >= ?", Time.zone.now.beginning_of_day)
      when "this_week"
        scope.where("created_at >= ?", Time.zone.now.beginning_of_week)
      when "this_month"
        scope.where("created_at >= ?", Time.zone.now.beginning_of_month)
      when "last_month"
        start = Time.zone.now.beginning_of_month.prev_month
        finish = Time.zone.now.beginning_of_month
        scope.where(created_at: start...finish)
      when "last_year"
        start = Time.zone.now.beginning_of_year.prev_year
        finish = Time.zone.now.beginning_of_year
        scope.where(created_at: start...finish)
      else
        scope
      end
    end
  end
end
