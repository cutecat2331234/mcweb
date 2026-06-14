# frozen_string_literal: true

module Community
  class CreateSmallActionPost < ApplicationService
    def initialize(topic:, actor:, body:)
      @topic = topic
      @actor = actor
      @body = body.to_s.strip
    end

    def call
      return ServiceResult.failure(error: "Small action body is required.") if @body.blank?

      post = nil
      @topic.with_lock do
        floor_number = @topic.posts.maximum(:floor_number).to_i + 1
        post = Community::Post.create!(
          topic: @topic,
          user: @actor,
          floor_number: floor_number,
          body: @body,
          post_type: "small_action",
          status: "published"
        )
      end

      ServiceResult.success(post)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
