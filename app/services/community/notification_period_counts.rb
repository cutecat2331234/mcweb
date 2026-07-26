# frozen_string_literal: true

module Community
  class NotificationPeriodCounts
    def self.call(scope, now: Time.zone.now)
      new(scope: scope, now: now).call
    end

    def initialize(scope:, now:)
      @scope = scope
      @now = now
    end

    def call
      periods = Community::NotificationPeriodFilters::PERIODS
      expressions = periods.map do |period|
        range = Community::NotificationPeriodScope.range_for(period, now: @now)
        count_expression.filter(range_condition(range))
      end
      values = @scope.unscope(:order).pick(*expressions)

      periods.zip(Array(values)).to_h.transform_values(&:to_i)
    end

    private

    def range_condition(range)
      created_at = Notification.arel_table[:created_at]
      condition = created_at.gteq(range.begin)
      return condition unless range.end

      upper_condition = if range.exclude_end?
        created_at.lt(range.end)
      else
        created_at.lteq(range.end)
      end
      condition.and(upper_condition)
    end

    def count_expression
      Arel::Nodes::NamedFunction.new("COUNT", [ Arel.star ])
    end
  end
end
