# frozen_string_literal: true

module Community
  class MarkTopicSolved < ApplicationService
    def initialize(user:, topic:, post:)
      @user = user
      @topic = topic
      @post = post
    end

    def call
      unless @user && Community::ForumAccess.topic_visible?(topic: @topic, user: @user)
        return ServiceResult.failure(error: :topic_not_available)
      end

      return ServiceResult.failure(error: :this_topic_is_archived) if @topic.archived_at.present?

      unless can_mark?
        return ServiceResult.failure(error: :you_are_not_allowed_to_mark_this_topic_as_solved)
      end

      if @post.forum_topic_id != @topic.id
        return ServiceResult.failure(error: :post_does_not_belong_to_this_topic)
      end

      unless PostAccess.readable?(post: @post, user: @user)
        return ServiceResult.failure(error: :post_not_available)
      end

      auto_close_result = nil
      Community::Topic.transaction do
        @topic.update!(solved_post: @post)
        auto_close_result = auto_close_on_solved!
        raise ActiveRecord::Rollback if auto_close_result&.failure?
      end
      return auto_close_result if auto_close_result&.failure?

      award_solution_points
      Community::NotifyTopicSolved.call(topic: @topic, post: @post, actor: @user)
      Community::DispatchForumEventWebhook.call(
        event_type: "topic.solved",
        topic: @topic,
        post: @post
      )
      ServiceResult.success(@topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    # Reward the answer author when their post is accepted as the solution.
    # Keyed on source = the topic, so a topic's solution awards at most once,
    # preventing solve/unsolve farming even if the accepted post changes.
    def award_solution_points
      return if @user.id == @post.user_id

      Community::AwardPoints.for_rule(
        user: @post.user,
        rule: "solution_accepted",
        source: @topic,
        default: 15
      )
    rescue StandardError => e
      Rails.logger.error(
        "[AwardPoints] solution_accepted failed for topic=#{@topic.id}: " \
        "#{e.class}: #{e.message}"
      )
    end

    def can_mark?
      Community::SectionModeration.can_mark_solved?(user: @user, topic: @topic)
    end

    def auto_close_on_solved!
      return unless SiteSetting.get("forum.auto_close_on_solved", "0") == "1"
      return if @topic.locked?

      @topic.update!(locked: true)
      actor = Community::SystemActor.user || @user
      Community::CreateSmallActionPost.call(
        topic: @topic,
        actor: actor,
        body: I18n.t("mcweb.forum.small_actions.topic_solved_closed")
      )
    end
  end
end
