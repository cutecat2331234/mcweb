# frozen_string_literal: true

module Community
  class TopicsController < ApplicationController
    before_action :require_login, only: %i[new create toggle_subscription moderate]
    before_action :set_section, only: %i[new create]
    before_action :set_topic, only: %i[show toggle_subscription moderate]

    def show
      @topic.record_view!
      mark_topic_read!

      @pagy, posts = pagy(
        @topic.posts.chronological.includes(:user, :quoted_post, :reactions),
        limit: 20
      )

      render inertia: "Community/Topics/Show", props: {
        topic: serialize_topic_detail(
          @topic,
          watching: watching_topic?,
          can_moderate: can_moderate_topic?
        ),
        posts: posts.map { |post| serialize_post(post, current_user: current_user) },
        pagination: pagy_props(@pagy),
        canReply: logged_in? && !@topic.locked?,
        reactionEmojis: Community::ToggleReaction::ALLOWED_EMOJI
      }
    end

    def new
      render inertia: "Community/Topics/New", props: {
        section: {
          name: @section.name,
          slug: @section.slug,
          url: forum_section_path(@section)
        }
      }
    end

    def create
      result = Community::CreateTopic.call(
        user: current_user,
        section: @section,
        title: topic_params[:title],
        body: topic_params[:body],
        ip_address: request.remote_ip
      )

      if result.success?
        redirect_to forum_topic_path(result.value), notice: "主题已创建。"
      else
        render inertia: "Community/Topics/New",
               props: {
                 section: {
                   name: @section.name,
                   slug: @section.slug,
                   url: forum_section_path(@section)
                 }
               },
               status: :unprocessable_entity,
               errors: topic_errors(result)
      end
    end

    def toggle_subscription
      result = Community::ToggleSubscription.call(user: current_user, topic: @topic)

      if result.success?
        redirect_to forum_topic_path(@topic), notice: result.value[:watching] ? "已关注此主题。" : "已取消关注。"
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def moderate
      result = Community::ModerateTopic.call(
        user: current_user,
        topic: @topic,
        action: params[:action_type]
      )

      if result.success?
        redirect_to forum_topic_path(@topic), notice: "主题已更新。"
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    private

    def set_section
      @section = Community::Section.find_by!(slug: params[:section_id])
    end

    def set_topic
      @topic = Community::Topic.includes(:section, :user).find_by!(public_id: params[:id])
    end

    def topic_params
      params.require(:topic).permit(:title, :body)
    end

    def topic_errors(result)
      errors = {}
      errors[:title] = Array(result.errors[:title]).first if result.errors&.dig(:title)
      errors[:body] = Array(result.errors[:body]).first if result.errors&.dig(:body)
      errors[:title] ||= result.error if result.error.present? && errors.empty?
      errors[:body] ||= result.error if result.error.present? && errors[:title].blank?
      errors
    end

    def mark_topic_read!
      return unless logged_in?

      last_floor = @topic.posts.maximum(:floor_number).to_i
      Community::ReadState.mark_read!(current_user, @topic, floor: last_floor)
    end

    def watching_topic?
      return false unless logged_in?

      Community::Subscription.exists?(user: current_user, subscribable: @topic)
    end

    def can_moderate_topic?
      current_user&.permission?("forum.topics.lock")
    end
  end
end
