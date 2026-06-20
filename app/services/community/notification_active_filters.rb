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
        label = @category == "commerce" ? I18n.t("mcweb.forum.notifications.category_commerce") : I18n.t("mcweb.forum.notifications.category_forum")
        items << { param: "category", label: label, value: @category }
      end
      items << { param: "read", label: I18n.t("mcweb.forum.notifications.unread_only"), value: "unread" } if @read == "unread"
      items << { param: "period", label: period_label(@period), value: @period } if @period.present?
      if @type.present?
        items << { param: "type", label: NotificationTypeLabels.label_for(@type), value: @type }
      end
      items
    end

  private

    def period_label(period)
      I18n.t("mcweb.forum.notifications.periods.#{period}", default: period)
    end
  end
end
