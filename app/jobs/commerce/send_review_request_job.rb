# frozen_string_literal: true

module Commerce
  class SendReviewRequestJob < ApplicationJob
    queue_as :default

    def perform(order_id)
      order = Commerce::Order.find_by(id: order_id)
      return unless order

      Commerce::SendReviewRequest.call(order: order)
    end
  end
end
