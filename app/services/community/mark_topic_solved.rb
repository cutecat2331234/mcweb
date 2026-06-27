# frozen_string_literal: true

module Community
  class MarkTopicSolved < ApplicationService
    def initialize(user:, topic:, post:)
      @user = user
      @topic = topic
      @post = post
    end

    def call
      unless can_mark?
        return ServiceResult.failure(error: "You are not allowed to mark this topic as solved.")
      end

      if @post.forum_topic_id != @topic.id
        return ServiceResult.failure(error: "Post does not belong to this topic.")
      end

      unless PostAccess.readable?(post: @post, user: @user)
        return ServiceResult.failure(error: "Post not available.")
      end

      @topic.update!(solved_post: @post)
      award_solution_points
      Community::NotifyTopicSolved.call(topic: @topic, post: @post, actor: @user)
      Community::DispatchForumEventWebhook.call(event_type: "topic.solved", topic: @topic, post: @post)
      auto_close_on_solved!
      ServiceResult.success(@topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    # Reward the answer author when their post is accepted as the solution.
    # Keyed on source = the topic, so a topic's solution awards at most once,
    # preventing solve/unsolve farming even if the accepted post changes.
    def award_solution_points
      Community::AwardPoints.for_rule(user: @post.user, rule: "solution_accepted", source: @topic, default: 15)
    rescue StandardError => e
      Rails.logger.error("[AwardPoints] solution_accepted failed for topic=#{@topic.id}: #{e.class}: #{e.message}")
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
