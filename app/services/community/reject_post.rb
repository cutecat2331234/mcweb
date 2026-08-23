# frozen_string_literal: true

module Community
  class RejectPost < ApplicationService
    REASON_MAX_LENGTH = 1_000

    def initialize(actor:, post:, reason: nil)
      @actor = actor
      @post = post
      @topic = post.topic
      @reason = reason.to_s.strip
    end

    def call
      return failure("post_rejection_reason_required") if @reason.blank?
      return failure("post_rejection_reason_too_long") if @reason.length > REASON_MAX_LENGTH

      result = Community::Post.transaction do
        decision = Community::DecidePendingPost.call(
          actor: @actor,
          post: @post,
          decision: :reject
        )
        next decision if decision.failure?

        Community::InAppNotification.notify(
          user: @post.user,
          notification_type: "forum.post_rejected",
          key: "post_rejected",
          title_key: "mcweb.labels.notification_types.forum.post_rejected",
          body_key: "mcweb.labels.notification_bodies.forum.post_rejected",
          notification_body: @reason,
          title: @topic.title.truncate(60),
          metadata: {
            topic_id: @topic.public_id,
            post_id: @post.id,
            path: Rails.application.routes.url_helpers.forum_topic_path(
              @topic,
              anchor: "post-#{@post.id}"
            )
          }
        )

        Administration::AuditLogger.call(
          actor: @actor,
          action: "community.post_rejected",
          resource: @post,
          metadata: { reason: @reason },
          reason: @reason
        )

        ServiceResult.success(@post)
      end
      return result if result.failure?

      dispatch_rejection_event
      result
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def failure(code)
      ServiceResult.failure(error: code, code:)
    end

    def dispatch_rejection_event
      result = Community::DispatchForumEventWebhook.call(
        event_type: "post.rejected",
        topic: @topic,
        post: @post,
        extra: { reason: @reason }
      )
      return unless result.failure?

      Rails.logger.error(
        "[ForumApproval] rejection event dispatch failed post=#{@post.id} code=#{result.code}"
      )
    rescue StandardError => e
      Rails.logger.error(
        "[ForumApproval] rejection event dispatch failed post=#{@post.id} " \
        "error=#{e.class}: #{e.message}"
      )
    end
  end
end
