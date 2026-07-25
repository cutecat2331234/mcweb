# frozen_string_literal: true

module Community
  class RejectPost < ApplicationService
    def initialize(actor:, post:, reason: nil)
      @actor = actor
      @post = post
      @topic = post.topic
      @reason = reason.to_s.strip
    end

    def call
      decision = Community::DecidePendingPost.call(
        actor: @actor,
        post: @post,
        decision: :reject
      )
      return decision if decision.failure?

      Notification.create!(
        user: @post.user,
        notification_type: "forum.post_rejected",
        title: I18n.t("mcweb.labels.notification_types.forum.post_rejected"),
        body: @reason.presence || I18n.t("mcweb.labels.notification_bodies.forum.post_rejected", title: @topic.title.truncate(60)),
        metadata: { topic_id: @topic.public_id, post_id: @post.id, path: Rails.application.routes.url_helpers.forum_topic_path(@topic, anchor: "post-#{@post.id}") }
      )

      Community::DispatchForumEventWebhook.call(
        event_type: "post.rejected",
        topic: @topic,
        post: @post,
        extra: { reason: @reason.presence }
      )

      Administration::AuditLogger.call(
        actor: @actor,
        action: "community.post_rejected",
        resource: @post,
        metadata: { reason: @reason.presence }
      )

      ServiceResult.success(@post)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
