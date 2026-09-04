# frozen_string_literal: true

module Community
  class PublishScheduledTopic < ApplicationService
    def initialize(topic:)
      @topic = topic
    end

    def call
      user = @topic&.user
      unless Community::ForumAccess.topic_visible?(topic: @topic, user: user)
        return ServiceResult.failure(error: :topic_not_available)
      end

      return ServiceResult.failure(error: :topic_is_not_scheduled) unless @topic.scheduled_at.present?
      return ServiceResult.failure(error: :topic_is_not_ready) unless @topic.scheduled_at <= Time.current
      return ServiceResult.failure(error: :topic_already_published) unless @topic.draft?

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

      field_result = Community::ValidateTopicFieldValues.call(topic: @topic, user: user)
      return field_result if field_result.failure?

      needs_approval = nil
      opening_post = nil
      state_result = nil
      owner_id = user.id

      Community::Topic.transaction do
        user = User.lock.find_by(id: owner_id)
        if !user || user.deleted? || user.banned?
          state_result = ServiceResult.failure(
            error: user&.banned? ? :account_banned : :account_deleted
          )
          raise ActiveRecord::Rollback
        end

        @topic = Community::Topic.with_discarded.lock.find_by(id: @topic.id)
        unless @topic && @topic.user_id == user.id && @topic.scheduled_at.present? &&
            @topic.scheduled_at <= Time.current && @topic.draft?
          state_result = ServiceResult.failure(error: :topic_is_not_scheduled)
          raise ActiveRecord::Rollback
        end

        needs_approval = Community::RequiresPostApproval.required_for?(user: user)
        topic_status = needs_approval ? "hidden" : "published"
        post_status = needs_approval ? "pending_approval" : "published"
        opening_post = Community::Post.with_discarded.lock.find_by(
          forum_topic_id: @topic.id,
          floor_number: 1
        )
        @topic.update!(
          status: topic_status,
          scheduled_at: nil,
          last_posted_at: Time.current
        )
        opening_post&.update!(status: post_status) if opening_post && opening_post.status != post_status
        Community::Subscription.subscribe!(user, @topic)
        Community::ReadState.mark_read!(user, @topic, floor: 1)
      end
      return state_result if state_result&.failure?

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
