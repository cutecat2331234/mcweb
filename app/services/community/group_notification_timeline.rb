# frozen_string_literal: true

module Community
  class GroupNotificationTimeline
    def self.call(groups)
      new(groups).sections
    end

    def initialize(groups)
      @groups = Array(groups)
    end

    def sections
      buckets = {
        "today" => [],
        "yesterday" => [],
        "this_week" => [],
        "this_month" => [],
        "last_month" => [],
        "earlier" => []
      }

      @groups.each do |group|
        bucket = bucket_for(group[:latest_at_ts])
        buckets[bucket] << group
      end

      [
        section("today", "今天", buckets["today"], default_expanded: true),
        section("yesterday", "昨天", buckets["yesterday"], default_expanded: true),
        section("this_week", "本周", buckets["this_week"], default_expanded: true),
        section("this_month", "本月", buckets["this_month"], default_expanded: false),
        section("last_month", "上月", buckets["last_month"], default_expanded: false),
        section("earlier", "更早", buckets["earlier"], default_expanded: false)
      ].compact
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

      "earlier"
    end

    def section(key, label, groups, default_expanded:)
      return if groups.empty?

      {
        key: key,
        label: label,
        count: groups.size,
        groups: groups,
        default_expanded: default_expanded
      }
    end
  end
end
