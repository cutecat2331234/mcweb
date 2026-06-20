# frozen_string_literal: true

module Community
  class PublishScheduledTopic < ApplicationService
    def initialize(topic:)
      @topic = topic
    end

    def call
      return ServiceResult.failure(error: "Topic is not scheduled.") unless @topic.scheduled_at.present?
      return ServiceResult.failure(error: "Topic is not ready.") unless @topic.scheduled_at <= Time.current
      return ServiceResult.failure(error: "Topic already published.") unless @topic.draft?

      tag_ids = @topic.tags.pluck(:id)
      required_result = Community::ValidateSectionRequiredTags.call(
        section: @topic.section,
        tag_ids: tag_ids
      )
      return required_result if required_result.failure?

      group_result = Community::ValidateSectionTagGroups.call(
        section: @topic.section,
        tag_ids: tag_ids
      )
      return group_result if group_result.failure?

      if @topic.section.prefix_required? && @topic.prefix.blank?
        return ServiceResult.failure(error: "section_topic_prefix_required")
      end

      user = @topic.user
      needs_approval = Community::RequiresPostApproval.required_for?(user: user)
      topic_status = needs_approval ? "hidden" : "published"
      post_status = needs_approval ? "pending_approval" : "published"
      opening_post = @topic.posts.first

      Community::Topic.transaction do
        @topic.update!(
          status: topic_status,
          scheduled_at: nil,
          last_posted_at: Time.current
        )
        opening_post&.update!(status: post_status) if opening_post && opening_post.status != post_status
        Community::Subscription.subscribe!(user, @topic)
        Community::ReadState.mark_read!(user, @topic, floor: 1)
      end

      if needs_approval
        Community::NotifyPendingPost.call(post: opening_post.reload) if opening_post
      elsif opening_post
        Community::PublishPostSideEffects.call(post: opening_post.reload)
      end
      Community::CheckAutoBadges.call(user: user)

      ServiceResult.success(@topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
