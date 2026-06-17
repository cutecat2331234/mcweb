# frozen_string_literal: true

module Commerce
  class ShippingAddress < ApplicationRecord
    self.table_name = "store_shipping_addresses"

    belongs_to :user

    validates :name, :phone, :line1, :city, :province, presence: true
    validates :phone, length: { maximum: 32 }

    scope :ordered, -> { order(default_address: :desc, updated_at: :desc) }

    def to_address_hash
      {
        "name" => name,
        "phone" => phone,
        "line1" => line1,
        "line2" => line2.to_s,
        "city" => city,
        "province" => province,
        "postal_code" => postal_code.to_s
      }
    end

    def summary_label
      [ label.presence, "#{province} #{city} #{line1}" ].compact.join(" · ")
    end
  end
end
