# frozen_string_literal: true

module Commerce
  class ExpirePendingOrdersJob < ApplicationJob
    queue_as :maintenance

    EXPIRY_WINDOW = 30.minutes

    def perform
      Commerce::Order
        .where(status: %w[pending awaiting_payment])
        .where("created_at < ?", EXPIRY_WINDOW.ago)
        .find_each do |order|
          Commerce::CancelOrder.call(order: order)
        end
    end
  end
end
