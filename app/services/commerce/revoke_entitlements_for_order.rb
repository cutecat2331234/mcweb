# frozen_string_literal: true

module Commerce
  class RevokeEntitlementsForOrder < ApplicationService
    def initialize(order:)
      @order = order
    end

    def call
      revoked = 0

      Commerce::Order.transaction do
        @order.lock!
        item_ids = @order.items.order(:id).pluck(:id)

        Commerce::UserEntitlement
          .where(source_order_item_id: item_ids, revoked_at: nil)
          .order(:id)
          .lock
          .each do |entitlement|
            entitlement.update!(revoked_at: Time.current)
            revoked += 1
          end
      end

      ServiceResult.success(revoked: revoked)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
