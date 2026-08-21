# frozen_string_literal: true

module Community
  class DeleteOwnTopic < ApplicationService
    def self.eligibility(user:, topic:)
      new(user: user, topic: topic).send(:eligibility)
    end

    def initialize(user:, topic:, request_id: nil)
      @user = user
      @topic = topic
      @request_id = request_id
    end

    def call
      result = nil
      Community::Topic.transaction do
        @topic.lock!
        result = eligibility
        raise ActiveRecord::Rollback if result.failure?

        result = DataGovernance::SoftDeleteContent.call(
          target: @topic,
          actor: @user,
          reason: I18n.t("mcweb.forum.topic_delete.author_reason"),
          request_id: @request_id
        )
        raise ActiveRecord::Rollback if result.failure?
      end
      return result if result.failure?

      Mcweb::Events.publish("forum.topic.deleted", topic: @topic, actor: @user)
      ServiceResult.success(topic: @topic, lifecycle: result.value[:record])
    rescue ActiveRecord::RecordNotFound
      failure("topic_delete_unavailable")
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    end

    private

    def eligibility
      return failure("topic_delete_unavailable") unless @user&.persisted? && @topic&.persisted?
      return failure("topic_delete_author_only") unless @topic.user_id == @user.id
      return failure("topic_delete_unavailable") unless @topic.published? && !@topic.soft_deleted?
      return failure("topic_delete_archived") if @topic.archived_at.present?
      return failure("topic_delete_announcement") if @topic.global_announcement?
      return failure("topic_delete_commerce_managed") if @topic.linked_product.present?
      return failure("topic_delete_locked") if @topic.locked?
      return failure("topic_delete_staff_managed") if staff_managed?
      return failure("topic_delete_has_replies") if other_user_replies?

      deletion_policy_result = DataGovernance::DeletionPolicy.call(target: @topic)
      return failure("topic_delete_evidence_protected") if deletion_policy_result.failure?

      deletion_policy = deletion_policy_result.value
      return failure("topic_delete_evidence_protected") unless deletion_policy.fetch(:allowed)

      ServiceResult.success(topic: @topic)
    end

    def staff_managed?
      @topic.pinned? ||
        @topic.featured? ||
        @topic.assigned_to_id.present? ||
        @topic.staff_notes.exists?
    end

    def other_user_replies?
      Community::Post.with_discarded
        .where(forum_topic_id: @topic.id)
        .where(post_type: "regular")
        .where.not(user_id: @user.id)
        .exists?
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code)
    end
  end
end
