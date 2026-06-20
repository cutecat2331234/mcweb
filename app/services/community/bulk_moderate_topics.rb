# frozen_string_literal: true

module Community
  class BulkModerateTopics < ApplicationService
    ALLOWED_ACTIONS = %w[lock unlock archive unarchive].freeze

    def initialize(user:, topic_public_ids:, action:, lock_reason: nil)
      @user = user
      @topic_public_ids = Array(topic_public_ids).map(&:to_s).uniq
      @action = action.to_s
      @lock_reason = lock_reason.to_s.strip.presence
    end

    def call
      return ServiceResult.failure(error: "topics_not_selected") if @topic_public_ids.empty?
      return ServiceResult.failure(error: "unsupported_bulk_action") unless ALLOWED_ACTIONS.include?(@action)

      moderated = 0
      failures = []

      Community::Topic.where(public_id: @topic_public_ids).find_each do |topic|
        unless Community::SectionModeration.can_moderate_topic_action?(user: @user, topic: topic, action: @action)
          failures << { id: topic.public_id, error: "unauthorized" }
          next
        end

        result = ModerateTopic.call(
          user: @user,
          topic: topic,
          action: @action,
          lock_reason: @lock_reason
        )
        if result.success?
          moderated += 1
        else
          failures << { id: topic.public_id, error: result.error }
        end
      end

      ServiceResult.success(moderated: moderated, failed: failures.size, failures: failures)
    end
  end
end
