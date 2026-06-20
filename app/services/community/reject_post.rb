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
      return ServiceResult.failure(error: "post_moderation_unauthorized") unless Community::SectionModeration.can_moderate_topic?(user: @actor, topic: @topic)
      return ServiceResult.failure(error: "post_not_pending_approval") unless @post.status == "pending_approval"

      Community::Post.transaction do
        @post.update!(status: "hidden")
        if @post.floor_number == 1 && @topic.status == "hidden"
          @topic.update!(status: "hidden")
        end
        Community::Post.sync_topic_counters!(@topic)
      end

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
