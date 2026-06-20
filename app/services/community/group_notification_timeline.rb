# frozen_string_literal: true

module Community
  class GroupNotificationTimeline
    BUCKETS = %w[today yesterday this_week this_month last_month last_year earlier].freeze

    def self.call(groups)
      new(groups).sections
    end

    def initialize(groups)
      @groups = Array(groups)
    end

    def sections
      buckets = BUCKETS.index_with { [] }

      @groups.each do |group|
        bucket = bucket_for(group[:latest_at_ts])
        buckets[bucket] << group
      end

      BUCKETS.filter_map do |key|
        section(key, buckets[key], default_expanded: %w[today yesterday this_week].include?(key))
      end
    end

  private

    def bucket_for(timestamp)
      time = Time.zone.at(timestamp.to_i)
      date = time.to_date
      today = Time.zone.today
      return "today" if date == today
      return "yesterday" if date == today - 1
      return "this_week" if date >= today.beginning_of_week
      return "this_month" if date >= today.beginning_of_month
      return "last_month" if date >= today.beginning_of_month.prev_month
      return "last_year" if date >= today.beginning_of_year.prev_year && date < today.beginning_of_year

      "earlier"
    end

    def section(key, groups, default_expanded:)
      return if groups.empty?

      {
        key: key,
        label: I18n.t("mcweb.forum.notification_timeline.#{key}"),
        count: groups.size,
        groups: groups,
        default_expanded: default_expanded
      }
    end
  end
end
