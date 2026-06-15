# frozen_string_literal: true

module Commerce
  class ExpirePendingOrdersJob < ApplicationJob
    queue_as :maintenance

    def perform
      window = expiry_window
      Commerce::Order
        .where(status: %w[pending awaiting_payment])
        .where("created_at < ?", window.ago)
        .find_each do |order|
          Commerce::CancelOrder.call(order: order)
        end
    end

    private

    def expiry_window
      minutes = SiteSetting.get("store.pending_order_expiry_minutes", "30").to_i
      minutes = 30 if minutes <= 0
      minutes.minutes
    end
  end
end
