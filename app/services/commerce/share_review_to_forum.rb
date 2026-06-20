# frozen_string_literal: true

module Commerce
  class ShareReviewToForum < ApplicationService
    def initialize(user:, review:)
      @user = user
      @review = review
      @product = review.product
    end

    def call
      return ServiceResult.failure(error: "share_review_unauthorized") unless @review.user_id == @user.id
      return ServiceResult.failure(error: "share_review_already_shared") if @review.forum_post_id.present?

      topic_result = Commerce::EnsureProductDiscussionTopic.call(product: @product, creator: @user)
      return topic_result unless topic_result.success?

      topic = topic_result.value
      stars = "★" * @review.rating + "☆" * (5 - @review.rating)
      body = "#{stars}\n\n#{@review.body.presence || I18n.t('mcweb.commerce.discussion.review_no_body')}\n\n#{Mcweb::Paths::APP_PREFIX}/store/products/#{@product.public_id}"

      post_result = Community::CreatePost.call(user: @user, topic: topic, body: body, skip_interval_check: true)
      return post_result unless post_result.success?

      @review.update!(forum_post_id: post_result.value.id)
      ServiceResult.success(post: post_result.value, topic: topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
