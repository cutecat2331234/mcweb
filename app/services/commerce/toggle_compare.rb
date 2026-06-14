# frozen_string_literal: true

module Commerce
  class ToggleCompare < ApplicationService
    MAX_ITEMS = 4

    def initialize(session:, product:)
      @session = session
      @product = product
    end

    def call
      ids = Array(@session[:compare_product_ids])
      public_id = @product.public_id

      if ids.include?(public_id)
        ids.delete(public_id)
        compared = false
      else
        return ServiceResult.failure(error: "最多只能对比 #{MAX_ITEMS} 件商品。") if ids.size >= MAX_ITEMS

        ids << public_id
        compared = true
      end

      @session[:compare_product_ids] = ids
      ServiceResult.success(compared: compared, count: ids.size, product_ids: ids)
    end
  end
end
