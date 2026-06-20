# frozen_string_literal: true

module Community
  class TopicListSortActiveFilters
    def self.call(sort:, default: "activity")
      new(sort: sort, default: default).chips
    end

    def initialize(sort:, default: "activity")
      @sort = sort.to_s
      @default = default.to_s
    end

    def chips
      return [] if @sort.blank? || @sort == @default

      label = I18n.t("mcweb.forum.topic_sort.#{@sort}", default: I18n.t("mcweb.forum.topic_sort_extended.#{@sort}", default: @sort))
      [ { param: "sort", label: I18n.t("mcweb.forum.sort_chip", label: label), value: @sort } ]
    end
  end
end
