# frozen_string_literal: true

module Commerce
  class CustomerOrderActiveFilters
    def self.call(query:, status:, created_after:, created_before:, status_label:)
      new(
        query: query,
        status: status,
        created_after: created_after,
        created_before: created_before,
        status_label: status_label
      ).chips
    end

    def initialize(query:, status:, created_after:, created_before:, status_label:)
      @query = query.to_s.strip
      @status = status.to_s
      @created_after = created_after.to_s.strip
      @created_before = created_before.to_s.strip
      @status_label = status_label
    end

    def chips
      items = []
      items << { param: "q", label: "订单号：#{@query}", value: @query } if @query.present?
      items << { param: "status", label: @status_label, value: @status } if @status.present?
      items << { param: "created_after", label: "起始于：#{@created_after}", value: @created_after } if @created_after.present?
      items << { param: "created_before", label: "截止于：#{@created_before}", value: @created_before } if @created_before.present?
      items
    end
  end
end
