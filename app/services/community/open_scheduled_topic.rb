# frozen_string_literal: true

module Community
  class OpenScheduledTopic < ApplicationService
    def initialize(topic:)
      @topic = topic
    end

    def call
      return ServiceResult.success unless @topic.auto_open_at&.<= Time.current
      return ServiceResult.success unless @topic.locked?

      actor = Community::SystemActor.user || @topic.user
      action_result = nil
      Community::Topic.transaction do
        @topic.update!(locked: false, lock_reason: nil, auto_open_at: nil)
        action_result = Community::CreateSmallActionPost.call(
          topic: @topic,
          actor: actor,
          body: I18n.t("mcweb.forum.small_actions.scheduled_reopen")
        )
        raise ActiveRecord::Rollback if action_result.failure?
      end
      return action_result if action_result.failure?

      ServiceResult.success(@topic)
    end
  end
end
