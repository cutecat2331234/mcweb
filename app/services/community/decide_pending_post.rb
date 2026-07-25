# frozen_string_literal: true

module Community
  # Applies a moderation decision only while the post is still pending.
  #
  # The topic lock matches the lock order used by reply allocation and topic
  # lifecycle services. Locking and reloading the post underneath it prevents a
  # stale approval form from overwriting a newer approve/reject decision.
  class DecidePendingPost < ApplicationService
    DECISION_STATUSES = {
      "approve" => "published",
      "reject" => "hidden"
    }.freeze

    def initialize(actor:, post:, decision:)
      @actor = actor
      @post = post
      @decision = decision.to_s
    end

    def call
      target_status = DECISION_STATUSES[@decision]
      return ServiceResult.failure(error: "invalid_post_moderation_decision") unless target_status

      topic = @post.topic
      result = nil

      topic.with_lock do
        @post.lock!

        if @post.forum_topic_id != topic.id
          result = ServiceResult.failure(error: "post_not_pending_approval")
          next
        end

        unless Community::SectionModeration.can_moderate_topic?(user: @actor, topic: topic)
          result = ServiceResult.failure(error: "post_moderation_unauthorized")
          next
        end

        unless @post.status == "pending_approval"
          result = ServiceResult.failure(error: "post_not_pending_approval")
          next
        end

        @post.update!(status: target_status)
        publish_opening_topic!(topic) if @decision == "approve"
        Community::Post.sync_topic_counters!(topic)
        result = ServiceResult.success(@post)
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def publish_opening_topic!(topic)
      return unless @post.floor_number == 1 && topic.status == "hidden"

      topic.update!(
        status: "published",
        last_posted_at: @post.created_at,
        last_post_user: @post.user
      )
    end
  end
end
