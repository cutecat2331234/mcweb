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
          skipped << "#{product.name}（未上架）"
          next
        end
        unless product.available?
          skipped << "#{product.name}（不可售）"
          next
        end

        public_id = product.public_id
        if ids.include?(public_id)
          skipped << "#{product.name}（已在对比）"
          next
        end
        if ids.size >= max_items
          limit_reached = true
          break
        end

        ids << public_id
        added += 1
      end

      skipped << "已达对比上限（#{max_items} 件）" if limit_reached && added.zero? && skipped.empty?

      @session[:compare_product_ids] = ids
      ServiceResult.success(added: added, skipped: skipped.uniq, count: ids.size, max_items: max_items)
    end
  end
end
