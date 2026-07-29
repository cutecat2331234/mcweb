# frozen_string_literal: true

module Community
  class ClosePoll < ApplicationService
    def initialize(user:, poll:)
      @user = user
      @poll = poll
    end

    def call
      topic = @poll.topic.reload
      unless @user && Community::ForumAccess.topic_visible?(topic: topic, user: @user)
        return ServiceResult.failure(error: :topic_not_available)
      end

      return ServiceResult.failure(error: :this_topic_is_archived) if topic.archived_at.present?

      unless @user.id == topic.user_id || @user.permission?("forum.topics.lock")
        return ServiceResult.failure(error: :not_allowed_to_close_poll)
      end

      return ServiceResult.failure(error: :poll_is_already_closed) unless @poll.open?

      finalize_result = nil
      Community::Poll.transaction do
        @poll.update!(closes_at: Time.current)
        finalize_result = Community::FinalizePollClosed.call(
          poll: @poll,
          actor: @user,
          body: I18n.t(
            "mcweb.forum.small_actions.poll_closed",
            user: @user.username,
            question: @poll.question
          )
        )
        raise ActiveRecord::Rollback if finalize_result.failure?
      end
      return finalize_result if finalize_result.failure?

      ServiceResult.success(@poll)
    rescue ActiveRecord::RecordNotFound
      ServiceResult.failure(error: :topic_not_available)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
