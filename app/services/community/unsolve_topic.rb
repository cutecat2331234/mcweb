# frozen_string_literal: true

module Community
  class UnsolveTopic < ApplicationService
    def initialize(user:, topic:)
      @user = user
      @topic = topic
    end

    def call
      unless can_unsolve?
        return ServiceResult.failure(error: "You are not allowed to unsolve this topic.")
      end

      @topic.update!(solved_post_id: nil)
      ServiceResult.success(@topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def can_unsolve?
      return true if @user.permission?("forum.topics.lock")

      @user.id == @topic.user_id
    end
  end
end
