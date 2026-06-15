# frozen_string_literal: true

module Commerce
  module WishlistCompareImportable
    extend ActiveSupport::Concern

    private

    def wishlist_importable_compare_count(compare_ids)
      compare_set = Array(compare_ids).to_set
      Commerce::WishlistItem
        .where(user: current_user)
        .includes(:product)
        .count do |item|
          product = item.product
          product.available? && !compare_set.include?(product.public_id)
        end
    end
  end
end
