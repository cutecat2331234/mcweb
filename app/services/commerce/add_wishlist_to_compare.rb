# frozen_string_literal: true

module Commerce
  class AddWishlistToCompare < ApplicationService
    def initialize(user:, session:)
      @user = user
      @session = session
    end

    def call
      ids = Array(@session[:compare_product_ids])
      max_items = Commerce::ToggleCompare.compare_max_items
      added = 0
      skipped = []
      limit_reached = false

      Commerce::WishlistItem.where(user: @user).includes(:product).order(created_at: :desc).find_each do |item|
        product = item.product
        if product.coming_soon?
          skipped << SkippedItemLabel.for_product(product.name, :coming_soon)
          next
        end
        unless product.available?
          skipped << SkippedItemLabel.for_product(product.name, :unavailable)
          next
        end
        unless Commerce::StoreFeatures.product_visible?(product)
          skipped << SkippedItemLabel.for_product(product.name, :feature_disabled)
          next
        end

        public_id = product.public_id
        if ids.include?(public_id)
          skipped << SkippedItemLabel.for_product(product.name, :already_in_compare)
          next
        end
        if ids.size >= max_items
          limit_reached = true
          skipped << SkippedItemLabel.for_product(product.name, :compare_full)
          next
        end

        ids << public_id
        added += 1
      end

      skipped << SkippedItemLabel.compare_limit(max_items) if limit_reached && added.zero? && skipped.empty?

      @session[:compare_product_ids] = ids
      ServiceResult.success(added: added, skipped: skipped.uniq, count: ids.size, max_items: max_items)
    end
  end
end
