# frozen_string_literal: true

module Commerce
  class ReplyToReview < ApplicationService
    def initialize(review:, actor:, body:)
      @review = review
      @actor = actor
      @body = body.to_s.strip
    end

    def call
      return ServiceResult.failure(error: "回复内容不能为空。") if @body.blank?
      unless @actor.permission?("store.products.manage") || @actor.permission?("admin.access")
        return ServiceResult.failure(error: "无权回复评价。")
      end

      @review.update!(merchant_reply: @body, merchant_replied_at: Time.current)
      ServiceResult.success(@review)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
