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
        "earlier" => []
      }

      @groups.each do |group|
        bucket = bucket_for(group[:latest_at_ts])
        buckets[bucket] << group
      end

      [
        section("today", "今天", buckets["today"], default_expanded: true),
        section("yesterday", "昨天", buckets["yesterday"], default_expanded: true),
        section("earlier", "更早", buckets["earlier"], default_expanded: false)
      ].compact
    end

  private

    def bucket_for(timestamp)
      time = Time.zone.at(timestamp.to_i)
      today = Time.zone.today
      return "today" if time.to_date == today
      return "yesterday" if time.to_date == today - 1

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
