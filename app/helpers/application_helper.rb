module ApplicationHelper
  def format_currency_from_cents(cents, currency)
    currency_code = currency.to_s.strip.upcase.presence || "XXX"
    number_to_currency(cents.to_i / 100.0, unit: currency_code, format: "%u %n")
  end

  def format_shipping_address(address)
    return nil unless address.is_a?(Hash) && address.values.any?(&:present?)

    parts = [
      address["name"],
      address["phone"],
      [ address["province"], address["city"] ].compact.join(" "),
      [ address["line1"], address["line2"] ].compact.join(" "),
      address["postal_code"]
    ].map(&:presence).compact
    parts.join("，")
  end
end
