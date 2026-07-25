# frozen_string_literal: true

module Community
  class CloseOwnTopic < ApplicationService
    def initialize(user:, topic:, action:, lock_reason: nil)
      @user = user
      @topic = topic
      @action = action.to_s
      @lock_reason = lock_reason.to_s.strip.presence
    end

    def call
      unless @user && Community::ForumAccess.topic_visible?(topic: @topic, user: @user)
        return ServiceResult.failure(error: "Topic not available.")
      end

      return ServiceResult.failure(error: "This topic is archived.") if @topic.archived_at.present?

      unless SiteSetting.get("forum.allow_op_close", "true") == "true"
        return ServiceResult.failure(error: "topic_close_disabled")
      end

      unless @topic.user_id == @user.id
        return ServiceResult.failure(error: "topic_close_author_only")
      end

      action_result = nil
      Community::Topic.transaction do
        case @action
        when "close"
          lock_body = I18n.t("mcweb.forum.small_actions.author_closed")
          @topic.update!(locked: true, lock_reason: @lock_reason || lock_body)
          action_result = Community::CreateSmallActionPost.call(
            topic: @topic,
            actor: @user,
            body: lock_body
          )
        when "reopen"
          reopen_body = I18n.t("mcweb.forum.small_actions.author_reopened")
          @topic.update!(locked: false, lock_reason: nil)
          action_result = Community::CreateSmallActionPost.call(
            topic: @topic,
            actor: @user,
            body: reopen_body
          )
        else
          return ServiceResult.failure(error: "Unknown action.")
        end
        raise ActiveRecord::Rollback if action_result.failure?
      end
      return action_result if action_result.failure?

      ServiceResult.success(@topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
