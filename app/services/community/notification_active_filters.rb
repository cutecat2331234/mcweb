# frozen_string_literal: true

module Community
  class NotificationActiveFilters
    def self.call(category:, read:, type:)
      new(category: category, read: read, type: type).chips
    end

    def initialize(category:, read:, type:)
      @category = category.to_s
      @read = read.to_s
      @type = type.to_s
    end

    def chips
      items = []
      if @category.present? && @category != "all"
        label = @category == "commerce" ? "商城" : "论坛"
        items << { param: "category", label: label, value: @category }
      end
      items << { param: "read", label: "仅未读", value: "unread" } if @read == "unread"
      if @type.present?
        items << { param: "type", label: NotificationTypeLabels.label_for(@type), value: @type }
      end
      items
    end
  end
end
