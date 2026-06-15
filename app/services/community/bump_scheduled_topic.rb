# frozen_string_literal: true

module Community
  class BumpScheduledTopic < ApplicationService
    def initialize(topic:)
      @topic = topic
    end

    def call
      return ServiceResult.success if @topic.status != "published"
      return ServiceResult.success unless @topic.auto_bump_at&.<= Time.current

      @topic.update!(bumped_at: Time.current, last_posted_at: Time.current, auto_bump_at: nil)
      actor = Community::SystemActor.user || @topic.user
      Community::CreateSmallActionPost.call(topic: @topic, actor: actor, body: "此主题已按计划自动提升。") if actor

      ServiceResult.success(@topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
