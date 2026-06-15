module ApplicationHelper
  include Pagy::Frontend

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
