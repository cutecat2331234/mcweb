# frozen_string_literal: true

module Commerce
  class ProductPrerequisite < ApplicationRecord
    self.table_name = "store_product_prerequisites"

    belongs_to :product, class_name: "Commerce::Product", foreign_key: :store_product_id
    belongs_to :required_product, class_name: "Commerce::Product", foreign_key: :required_product_id

    enum :requirement_mode, { ever_purchased: "ever_purchased", active: "active" }, validate: true

    validate :cannot_require_self

    private

    def cannot_require_self
      return if store_product_id.blank? || required_product_id.blank?
      return unless store_product_id == required_product_id

      errors.add(:required_product_id, "cannot be the same as the product")
    end
  end
end
