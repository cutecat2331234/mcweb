# frozen_string_literal: true

module Commerce
  module ShippingMethods
    DEFAULT_JSON = [
      { "code" => "standard", "label" => "标准配送", "cents" => 800, "delivery_days_min" => 3, "delivery_days_max" => 5 },
      { "code" => "express", "label" => "加急配送", "cents" => 2000, "delivery_days_min" => 1, "delivery_days_max" => 2 }
    ].freeze

    module_function

    def stored_list
      raw = SiteSetting.get("store.shipping_methods", nil)
      parsed = raw.present? ? JSON.parse(raw) : DEFAULT_JSON
      Array(parsed).filter_map do |entry|
        next unless entry.is_a?(Hash) && entry["code"].present?

        {
          "code" => entry["code"].to_s,
          "label" => entry["label"].presence || entry["code"].to_s,
          "cents" => entry["cents"].to_i,
          "delivery_days_min" => entry["delivery_days_min"].presence&.to_i,
          "delivery_days_max" => entry["delivery_days_max"].presence&.to_i
        }
      end.presence || DEFAULT_JSON.map(&:dup)
    rescue JSON::ParserError
      DEFAULT_JSON.map(&:dup)
    end

    def list
      apply_flat_shipping_to_standard!(stored_list.map(&:dup))
    end

    def apply_flat_shipping_to_standard!(methods)
      flat = SiteSetting.get("store.flat_shipping_cents", "0").to_i
      methods.map { |entry| entry["code"] == "standard" ? entry.merge("cents" => flat) : entry }
    end
    private_class_method :apply_flat_shipping_to_standard!

    def find(code)
      list.find { |method| method["code"] == code.to_s }
    end

    def label_for(code)
      find(code)&.dig("label") || code.to_s
    end

    def delivery_estimate_label(method)
      min = method["delivery_days_min"].to_i
      max = method["delivery_days_max"].to_i
      return nil if min <= 0 && max <= 0
      return "预计 #{min} 天送达" if max <= 0 || min == max
      return "预计 #{max} 天送达" if min <= 0

      "预计 #{min}-#{max} 天送达"
    end
  end
end
