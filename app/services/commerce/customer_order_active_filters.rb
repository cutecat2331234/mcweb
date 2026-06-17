# frozen_string_literal: true

module Commerce
  class CustomerOrderActiveFilters
    def self.call(query:, status:, created_after:, created_before:, min_total:, max_total:, status_label:, currency: "CNY")
      new(
        query: query,
        status: status,
        created_after: created_after,
        created_before: created_before,
        min_total: min_total,
        max_total: max_total,
        status_label: status_label,
        currency: currency
      ).chips
    end

    def initialize(query:, status:, created_after:, created_before:, min_total:, max_total:, status_label:, currency:)
      @query = query.to_s.strip
      @status = status.to_s
      @created_after = created_after.to_s.strip
      @created_before = created_before.to_s.strip
      @min_total = min_total.to_s.strip
      @max_total = max_total.to_s.strip
      @status_label = status_label
      @currency = currency
    end

    def chips
      items = []
      items << { param: "q", label: "订单号：#{@query}", value: @query } if @query.present?
      items << { param: "status", label: @status_label, value: @status } if @status.present?
      items << { param: "created_after", label: "起始于：#{@created_after}", value: @created_after } if @created_after.present?
      items << { param: "created_before", label: "截止于：#{@created_before}", value: @created_before } if @created_before.present?
      items << { param: "min_total", label: "最低金额：#{money_label(@min_total)}", value: @min_total } if @min_total.present?
      items << { param: "max_total", label: "最高金额：#{money_label(@max_total)}", value: @max_total } if @max_total.present?
      items
    end

  private

    def money_label(amount)
      unit = @currency == "CNY" ? "¥" : "$"
      "#{unit}#{amount}"
    end
  end
end
