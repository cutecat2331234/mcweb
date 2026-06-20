# frozen_string_literal: true

module Commerce
  class NotifyMerchantReviewReply < ApplicationService
    def initialize(review:)
      @review = review
    end

    def call
      user = @review.user
      product = @review.product
      path = "#{Mcweb::Paths::APP_PREFIX}/store/products/#{product.public_id}#reviews"

      Commerce::NotifyOrderEvent.call(
        user: user,
        notification_type: "commerce.merchant_review_reply",
        title: Commerce::InAppNotification.t("merchant_review_reply.title"),
        body: Commerce::InAppNotification.t("merchant_review_reply.body", product: product.name),
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
