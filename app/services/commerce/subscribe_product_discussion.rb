# frozen_string_literal: true

module Commerce
  class SubscribeProductDiscussion < ApplicationService
    def initialize(user:, product:)
      @user = user
      @product = product
    end

    def call
      topic_result = Commerce::EnsureProductDiscussionTopic.call(product: @product)
      return topic_result unless topic_result.success?

      Community::Subscription.subscribe!(@user, topic_result.value)
      ServiceResult.success(topic: topic_result.value)
    end
  end
end
