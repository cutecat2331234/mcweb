# frozen_string_literal: true

module Community
  class ArchiveScheduledTopic < ApplicationService
    def initialize(topic:)
      @topic = topic
    end

    def call
      return ServiceResult.success if @topic.archived_at.present?
      return ServiceResult.success unless @topic.auto_archive_at&.<= Time.current

      actor = Community::SystemActor.user || @topic.user
      action_result = nil
      Community::Topic.transaction do
        @topic.update!(archived_at: Time.current, auto_archive_at: nil)
        action_result = Community::CreateSmallActionPost.call(
          topic: @topic,
          actor: actor,
          body: I18n.t("mcweb.forum.small_actions.scheduled_archive")
        )
        raise ActiveRecord::Rollback if action_result.failure?
      end
      return action_result if action_result.failure?

      ServiceResult.success(@topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
