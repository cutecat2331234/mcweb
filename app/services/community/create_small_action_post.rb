# frozen_string_literal: true

module Community
  class CreateSmallActionPost < ApplicationService
    def initialize(topic:, actor:, body:)
      @topic = topic
      @actor = actor
      @body = body.to_s.strip
    end

    def call
      return ServiceResult.failure(error: :small_action_body_required) if @body.blank?

      post = nil
      state_result = nil
      Community::Post.transaction do
        @actor = User.lock.find(@actor.id)
        state_result = account_write_access_result
        raise ActiveRecord::Rollback if state_result.failure?

        @topic.with_lock do
          floor_number = @topic.posts.with_discarded.maximum(:floor_number).to_i + 1
          post = Community::Post.create!(
            topic: @topic,
            user: @actor,
            floor_number: floor_number,
            body: @body,
            post_type: "small_action",
            status: "published"
          )
          @topic.update!(last_posted_at: post.created_at, last_post_user: @actor)
        end
      end
      return state_result if state_result&.failure?

      ServiceResult.success(post)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def account_write_access_result
      return ServiceResult.failure(error: :account_deleted) if @actor.deleted?
      return ServiceResult.failure(error: :account_banned) if @actor.banned?

      ServiceResult.success
    end
  end
end
