# frozen_string_literal: true

module Commerce
  class CreateFulfillment < ApplicationService
    MAX_RETRIES = 3

    def initialize(order_item:)
      @order_item = order_item
    end

    def call
      existing = Commerce::Fulfillment.find_by(order_item: @order_item)
      return ServiceResult.success(existing) if existing

      retries = 0

      begin
        fulfillment = Commerce::Fulfillment.transaction do
          Commerce::Fulfillment.create!(
            order: @order_item.order,
            order_item: @order_item,
            delivery_id: generate_delivery_id,
            status: "pending"
          )
        end

        ServiceResult.success(fulfillment)
      rescue ActiveRecord::RecordNotUnique
        retries += 1
        retry if retries < MAX_RETRIES
        ServiceResult.failure(error: "Unable to generate unique delivery ID.")
      rescue ActiveRecord::RecordInvalid => e
        ServiceResult.failure(errors: e.record.errors.to_hash)
      end
    end

    private

    def generate_delivery_id
      "dlv_#{SecureRandom.alphanumeric(24)}"
    end
  end
end
