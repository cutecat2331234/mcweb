# frozen_string_literal: true

module Commerce
  class ToggleCompare < ApplicationService
    def initialize(session:, product:)
      @session = session
      @product = product
    end

    def call
      ids = Array(@session[:compare_product_ids])
      public_id = @product.public_id
      max_items = compare_max_items

      if ids.include?(public_id)
        ids.delete(public_id)
        compared = false
      else
        return ServiceResult.failure(error: I18n.t("mcweb.services.errors.compare_limit_reached", count: max_items)) if ids.size >= max_items

        ids << public_id
        compared = true
      end

      @session[:compare_product_ids] = ids
      ServiceResult.success(compared: compared, count: ids.size, product_ids: ids, max_items: max_items)
    end

    def self.compare_max_items
      max = SiteSetting.get("store.compare_max_items", "4").to_i
      max.positive? ? max : 4
    end

    private

    def compare_max_items
      self.class.compare_max_items
    end
  end
end
