# frozen_string_literal: true

module Commerce
  class NotifyMerchantReviewReply < ApplicationService
    def initialize(review:)
      @review = review
    end

    def call
      user = @review.user
      product = @review.product
      path = "/store/products/#{product.public_id}#reviews"

      Commerce::NotifyOrderEvent.call(
        user: user,
        notification_type: "commerce.merchant_review_reply",
        title: "商家回复了你的评价",
        body: "「#{product.name}」的评价收到商家回复。",
        path: path
      )

      if NotificationPreference.enabled?(user, channel: "email", notification_type: "commerce.merchant_review_reply")
        MailDeliveryJob.perform_later(
          "Commerce::OrderMailer",
          "merchant_review_reply",
          "deliver_now",
          args: [ @review.id ]
        )
      end

      ServiceResult.success
    end
  end
end
