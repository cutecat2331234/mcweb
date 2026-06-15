# frozen_string_literal: true

module Community
  class PublishTopicDraft < ApplicationService
    def initialize(user:, topic:)
      @user = user
      @topic = topic
    end

    def call
      return ServiceResult.failure(error: "Not your draft.") unless @topic.user_id == @user.id
      return ServiceResult.failure(error: "Topic is not a draft.") unless @topic.status == "draft"

      post = @topic.posts.first
      return ServiceResult.failure(error: "Draft body is required.") unless post&.body.present?

      unless @topic.section.allowed?(@user, :create_topic)
        return ServiceResult.failure(error: "You are not allowed to create topics in this section.")
      end

      return ServiceResult.failure(error: "You are muted in this section.") if Community::Mute.muted?(@user, section: @topic.section)

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
        return ServiceResult.failure(error: "此分区要求选择主题前缀。")
      end

      if Community::TrustLevel.contains_link?(post.body) && !Community::TrustLevel.can_post_links?(@user)
        return ServiceResult.failure(error: "New members cannot post links. Participate more to unlock this.")
      end

      Community::Topic.transaction do
        @topic.update!(status: "published", last_posted_at: Time.current, last_post_user: @user)
        Community::Subscription.subscribe!(@user, @topic)
        Community::ReadState.mark_read!(@user, @topic, floor: post.floor_number)
      end

      Community::ProcessMentions.call(body: post.body, author: @user, post: post, topic: @topic)
      Community::NotifySectionTopic.call(topic: @topic)
      Community::NotifyFollowedUserTopic.call(topic: @topic)
      if @topic.tags.any?
        Community::NotifyTagTopic.call(topic: @topic, tags: @topic.tags)
      end
      Community::CheckAutoBadges.call(user: @user)
      ServiceResult.success(@topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
