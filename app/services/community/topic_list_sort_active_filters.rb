# frozen_string_literal: true

module Community
  class TopicListSortActiveFilters
    LABELS = {
      "activity" => "最近活跃",
      "hot" => "热门",
      "newest" => "最新发布",
      "replies" => "最多回复",
      "views" => "最多浏览",
      "latest" => "最新回复",
      "unread" => "未读最多"
    }.freeze

    def self.call(sort:, default: "activity")
      new(sort: sort, default: default).chips
    end

    def initialize(sort:, default: "activity")
      @sort = sort.to_s
      @default = default.to_s
    end

    def chips
      return [] if @sort.blank? || @sort == @default

      label = LABELS[@sort] || @sort
      [ { param: "sort", label: "排序：#{label}", value: @sort } ]
    end
  end
end
