# frozen_string_literal: true

module Community
  class ArchiveScheduledTopic < ApplicationService
    def initialize(topic:)
      @topic = topic
    end

    def call
      return ServiceResult.success if @topic.archived_at.present?
      return ServiceResult.success unless @topic.auto_archive_at&.<= Time.current

      @topic.update!(archived_at: Time.current, auto_archive_at: nil)
      actor = Community::SystemActor.user || @topic.user
      if actor
        Community::CreateSmallActionPost.call(topic: @topic, actor: actor, body: "此主题已到达预定时间并自动归档。")
      end

      ServiceResult.success(@topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
