# frozen_string_literal: true

module Community
  class NotificationActiveFilters
    def self.call(category:, read:, type:, period: nil)
      new(category: category, read: read, type: type, period: period).chips
    end

    def initialize(category:, read:, type:, period: nil)
      @category = category.to_s
      @read = read.to_s
      @type = type.to_s
      @period = period.to_s
    end

    def chips
      items = []
      if @category.present? && @category != "all"
        label = @category == "commerce" ? "商城" : "论坛"
        items << { param: "category", label: label, value: @category }
      end
      items << { param: "read", label: "仅未读", value: "unread" } if @read == "unread"
      items << { param: "period", label: "仅今日", value: "today" } if @period == "today"
      if @type.present?
        items << { param: "type", label: NotificationTypeLabels.label_for(@type), value: @type }
      end
      items
    end
  end
end
