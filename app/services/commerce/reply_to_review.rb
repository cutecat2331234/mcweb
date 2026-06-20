# frozen_string_literal: true

module Commerce
  class ReplyToReview < ApplicationService
    def initialize(review:, actor:, body:)
      @review = review
      @actor = actor
      @body = body.to_s.strip
    end

    def call
      return ServiceResult.failure(error: "merchant_reply_blank") if @body.blank?
      unless @actor.permission?("store.products.manage") || @actor.permission?("admin.access")
        return ServiceResult.failure(error: "merchant_reply_unauthorized")
      end

      @review.update!(merchant_reply: @body, merchant_replied_at: Time.current)
      Commerce::NotifyMerchantReviewReply.call(review: @review)
      ServiceResult.success(@review)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
