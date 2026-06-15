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
      items << { param: "period", label: period_label(@period), value: @period } if @period.present?
      if @type.present?
        items << { param: "type", label: NotificationTypeLabels.label_for(@type), value: @type }
      end
      items
    end

  private

    def period_label(period)
      case period
      when "today" then "仅今日"
      when "this_week" then "本周"
      when "this_month" then "本月"
      else period
      end
    end
  end
end
