# frozen_string_literal: true

module Community
  class UnsolveTopic < ApplicationService
    def initialize(user:, topic:)
      @user = user
      @topic = topic
    end

    def call
      unless @user && Community::ForumAccess.topic_visible?(topic: @topic, user: @user)
        return ServiceResult.failure(error: :topic_not_available)
      end

      return ServiceResult.failure(error: :this_topic_is_archived) if @topic.archived_at.present?

      unless can_unsolve?
        return ServiceResult.failure(error: :you_are_not_allowed_to_unsolve_this_topic)
      end

      @topic.update!(solved_post_id: nil)
      ServiceResult.success(@topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def can_unsolve?
      Community::SectionModeration.can_mark_solved?(user: @user, topic: @topic)
    end
  end
end
