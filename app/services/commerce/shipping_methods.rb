# frozen_string_literal: true

module Commerce
  module ShippingMethods
    DEFAULT_JSON = [
      { "code" => "standard", "label" => "标准配送", "cents" => 800 },
      { "code" => "express", "label" => "加急配送", "cents" => 2000 }
    ].freeze

    module_function

    def list
      raw = SiteSetting.get("store.shipping_methods", nil)
      parsed = raw.present? ? JSON.parse(raw) : DEFAULT_JSON
      methods = Array(parsed).filter_map do |entry|
        next unless entry.is_a?(Hash) && entry["code"].present?

        {
          "code" => entry["code"].to_s,
          "label" => entry["label"].presence || entry["code"].to_s,
          "cents" => entry["cents"].to_i
        }
      end.presence || DEFAULT_JSON.map(&:dup)
      apply_flat_shipping_to_standard!(methods)
    rescue JSON::ParserError
      apply_flat_shipping_to_standard!(DEFAULT_JSON.map(&:dup))
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
  end
end
