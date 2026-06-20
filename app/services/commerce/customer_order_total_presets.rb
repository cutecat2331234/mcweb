# frozen_string_literal: true

module Commerce
  class CustomerOrderTotalPresets
    PRESET_KEYS = %w[under_100 100_500 over_500].freeze

    def self.call(min_total:, max_total:, **context)
      new(min_total: min_total, max_total: max_total, **context).presets
    end

    def initialize(min_total:, max_total:, query: nil, status: nil, created_after: nil, created_before: nil)
      @min_total = min_total.to_s.strip
      @max_total = max_total.to_s.strip
      @query = query.to_s.strip
      @status = status.to_s.strip
      @created_after = created_after.to_s.strip
      @created_before = created_before.to_s.strip
    end

    def presets
      preset_definitions.map do |preset|
        {
          key: preset[:key],
          label: I18n.t("mcweb.commerce.customer_orders.preset_#{preset[:key]}"),
          min_total: preset[:min_total],
          max_total: preset[:max_total],
          active: active?(preset),
          href: Rails.application.routes.url_helpers.store_orders_path(path_params(preset))
        }
      end
    end

  private

    def preset_definitions
      [
        { key: "under_100", min_total: nil, max_total: "100" },
        { key: "100_500", min_total: "100", max_total: "500" },
        { key: "over_500", min_total: "500", max_total: nil }
      ]
    end

    def path_params(preset)
      {
        q: @query.presence,
        status: @status.presence,
        created_after: @created_after.presence,
        created_before: @created_before.presence,
        min_total: preset[:min_total],
        max_total: preset[:max_total]
      }.compact
    end

    def active?(preset)
      preset_min = preset[:min_total].to_s
      preset_max = preset[:max_total].to_s
      @min_total == preset_min && @max_total == preset_max
    end
  end
end
