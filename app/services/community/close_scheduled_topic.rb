# frozen_string_literal: true

module Community
  class CloseScheduledTopic < ApplicationService
    def initialize(topic:)
      @topic = topic
    end

    def call
      return ServiceResult.success if @topic.locked?
      return ServiceResult.success unless @topic.auto_close_at&.<= Time.current

      @topic.update!(locked: true, auto_close_at: nil)
      actor = Community::SystemActor.user || @topic.user
      Community::CreateSmallActionPost.call(topic: @topic, actor: actor, body: "此主题已到达预定时间并自动关闭。") if actor

      ServiceResult.success(@topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
