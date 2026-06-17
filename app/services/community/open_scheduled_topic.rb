# frozen_string_literal: true

module Community
  class OpenScheduledTopic < ApplicationService
    def initialize(topic:)
      @topic = topic
    end

    def call
      return ServiceResult.success unless @topic.auto_open_at&.<= Time.current
      return ServiceResult.success unless @topic.locked?

      @topic.update!(locked: false, lock_reason: nil, auto_open_at: nil)
      Community::CreateSmallActionPost.call(
        topic: @topic,
        actor: Community::SystemActor.user,
        body: "此主题已按计划自动重新开放。"
      )
      ServiceResult.success(@topic)
    end
  end
end
