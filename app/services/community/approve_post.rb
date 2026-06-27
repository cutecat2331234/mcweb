# frozen_string_literal: true

module Community
  class ApprovePost < ApplicationService
    def initialize(actor:, post:)
      @actor = actor
      @post = post
      @topic = post.topic
    end

    def call
      return ServiceResult.failure(error: "post_moderation_unauthorized") unless Community::SectionModeration.can_moderate_topic?(user: @actor, topic: @topic)
      return ServiceResult.failure(error: "post_not_pending_approval") unless @post.status == "pending_approval"

      Community::Post.transaction do
        @post.update!(status: "published")
        if @post.floor_number == 1 && @topic.status == "hidden"
          @topic.update!(
            status: "published",
            last_posted_at: @post.created_at,
            last_post_user: @post.user
          )
        end
        Community::Post.sync_topic_counters!(@topic)
      end

      Community::PublishPostSideEffects.call(post: @post.reload, dispatch_webhooks: false)
      award_post_points(@post)

      Notification.create!(
        user: @post.user,
        notification_type: "forum.post_approved",
        title: I18n.t("mcweb.labels.notification_types.forum.post_approved"),
        body: I18n.t("mcweb.labels.notification_bodies.forum.post_approved", title: @topic.title.truncate(60)),
        metadata: {
          topic_id: @topic.public_id,
          post_id: @post.id,
          path: Rails.application.routes.url_helpers.forum_topic_path(@topic, anchor: "post-#{@post.id}")
        }
      )

      Community::DispatchForumEventWebhook.call(
        event_type: "post.approved",
        topic: @topic,
        post: @post,
        extra: { approved_by_id: @actor.id, approved_by_username: @actor.username }
      )
      Administration::AuditLogger.call(
        actor: @actor,
        action: "community.post_approved",
        resource: @post
      )

      ServiceResult.success(@post)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    # Award points to the author once their pending post is approved. Idempotent
    # on (author, "post_created", post); guarded so awarding never breaks approval.
    def award_post_points(post)
      Community::AwardPoints.for_rule(user: post.user, rule: "post_created", source: post, default: 5)
    rescue StandardError => e
      Rails.logger.error("[AwardPoints] post_created (approve) failed for post=#{post.id}: #{e.class}: #{e.message}")
    end
  end
end
