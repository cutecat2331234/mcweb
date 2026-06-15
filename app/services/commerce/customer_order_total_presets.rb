# frozen_string_literal: true

module Commerce
  class CustomerOrderTotalPresets
    PRESETS = [
      { key: "under_100", label: "¥100 以下", min_total: nil, max_total: "100" },
      { key: "100_500", label: "¥100–500", min_total: "100", max_total: "500" },
      { key: "over_500", label: "¥500 以上", min_total: "500", max_total: nil }
    ].freeze

    def self.call(min_total:, max_total:)
      new(min_total: min_total, max_total: max_total).presets
    end

    def initialize(min_total:, max_total:)
      @min_total = min_total.to_s.strip
      @max_total = max_total.to_s.strip
    end

    def presets
      PRESETS.map do |preset|
        {
          key: preset[:key],
          label: preset[:label],
          min_total: preset[:min_total],
          max_total: preset[:max_total],
          active: active?(preset),
          href: Rails.application.routes.url_helpers.store_orders_path(
            min_total: preset[:min_total],
            max_total: preset[:max_total]
          )
        }
      end
    end

  private

    def active?(preset)
      preset_min = preset[:min_total].to_s
      preset_max = preset[:max_total].to_s
      @min_total == preset_min && @max_total == preset_max
    end
  end
end
