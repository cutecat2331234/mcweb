# frozen_string_literal: true

module Community
  class TopicsController < ApplicationController
    include Community::TopicVisibility

    before_action :require_login, only: %i[new create update toggle_subscription toggle_bookmark moderate move merge mark_solved unsolve update_slow_mode]
    before_action :set_section, only: %i[new create]
    before_action :set_topic, only: %i[show update toggle_subscription toggle_bookmark moderate move mark_solved unsolve update_slow_mode]

    def show
      @topic.record_view!
      mark_topic_read!
      mark_topic_notifications_read!

      posts_scope = @topic.posts.chronological.includes(:user, :quoted_post, :parent_post, :reactions, :edits)
      posts_scope = filter_blocked_posts(posts_scope)

      @pagy, posts = pagy(posts_scope, limit: 20)

      render inertia: "Community/Topics/Show", props: {
        topic: serialize_topic_detail(
          @topic,
          watching: watching_topic?,
          bookmarked: bookmarked_topic?,
          can_moderate: can_moderate_topic?,
          can_move: can_move_topic?,
          can_edit: can_edit_topic?
        ),
        posts: posts.map { |post| serialize_post(post, current_user: current_user, can_moderate: can_moderate_topic?, solved_post_id: @topic.solved_post_id) },
        pagination: pagy_props(@pagy),
        canReply: logged_in? && !@topic.locked? && @topic.section.allowed?(current_user, :reply),
        canMarkSolved: logged_in? && (can_moderate_topic? || current_user.id == @topic.user_id),
        reactionEmojis: Community::ToggleReaction::ALLOWED_EMOJI,
        sections: can_move_topic? ? movable_sections : [],
        reportTopicUrl: logged_in? ? new_forum_report_path(reportable_type: "Community::Topic", reportable_id: @topic.id) : nil,
        poll: @topic.poll ? serialize_poll(@topic.poll) : nil,
        meta: {
          title: @topic.title,
          description: @topic.posts.first&.body&.truncate(160)
        }
      }
    end

    def new
      render inertia: "Community/Topics/New", props: {
        section: {
          name: @section.name,
          slug: @section.slug,
          url: forum_section_path(@section),
          prefixes: Array(@section.prefixes)
        }
      }
    end

    def create
      result = Community::CreateTopic.call(
        user: current_user,
        section: @section,
        title: topic_params[:title],
        body: topic_params[:body],
        tag_names: topic_params[:tags],
        poll_question: topic_params[:poll_question],
        poll_options: parse_poll_options(topic_params[:poll_options]),
        poll_closes_days: topic_params[:poll_closes_days],
        prefix: topic_params[:prefix],
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
                   url: forum_section_path(@section),
                   prefixes: Array(@section.prefixes)
                 }
               },
               status: :unprocessable_entity,
               errors: topic_errors(result)
      end
    end

    def update
      result = Community::EditTopic.call(
        user: current_user,
        topic: @topic,
        title: topic_params[:title],
        tag_names: topic_params[:tags]
      )

      if result.success?
        redirect_to forum_topic_path(@topic), notice: "主题已更新。"
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
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

    def toggle_bookmark
      result = Community::ToggleBookmark.call(user: current_user, topic: @topic)

      if result.success?
        redirect_to forum_topic_path(@topic), notice: result.value[:bookmarked] ? "已加入书签。" : "已移除书签。"
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

    def move
      section = Community::Section.find_by!(slug: params[:section_slug])
      result = Community::MoveTopic.call(user: current_user, topic: @topic, section: section)

      if result.success?
        redirect_to forum_topic_path(@topic), notice: "主题已移动。"
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def merge
      result = Community::MergeTopics.call(
        user: current_user,
        source: @topic,
        target_public_id: params[:target_topic_id]
      )

      if result.success?
        redirect_to forum_topic_path(result.value), notice: "主题已合并。"
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def mark_solved
      post = @topic.posts.find(params[:post_id])
      result = Community::MarkTopicSolved.call(user: current_user, topic: @topic, post: post)

      if result.success?
        redirect_to forum_topic_path(@topic, anchor: "post-#{post.id}"), notice: "已标记为已解决。"
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def unsolve
      result = Community::UnsolveTopic.call(user: current_user, topic: @topic)

      if result.success?
        redirect_to forum_topic_path(@topic), notice: "已取消已解决标记。"
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def update_slow_mode
      return redirect_to forum_topic_path(@topic), alert: "无权操作。" unless can_moderate_topic?

      seconds = params[:seconds].to_i
      @topic.update!(slow_mode_seconds: seconds.positive? ? seconds : nil)
      redirect_to forum_topic_path(@topic), notice: seconds.positive? ? "慢速模式已启用（#{seconds} 秒）。" : "慢速模式已关闭。"
    end

    private

    def set_section
      @section = Community::Section.find_by!(slug: params[:section_id])
    end

    def set_topic
      @topic = Community::Topic.includes(:section, :user, :tags, :poll, :solved_post).find_by!(public_id: params[:id])
      ensure_topic_visible!(@topic)
    end

    def topic_params
      params.require(:topic).permit(:title, :body, :tags, :poll_question, :poll_options, :poll_closes_days, :prefix)
    end

    def parse_poll_options(raw)
      raw.to_s.lines.map(&:strip).reject(&:blank?)
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

    def bookmarked_topic?
      return false unless logged_in?

      Community::Bookmark.exists?(user: current_user, topic: @topic)
    end

    def mark_topic_notifications_read!
      return unless logged_in?

      types = %w[forum.topic_reply forum.mention forum.section_topic]
      current_user.notifications.unread.where(notification_type: types).find_each do |notification|
        topic_id = notification.metadata["topic_id"]
        notification.mark_read! if topic_id == @topic.public_id
      end
    end

    def can_moderate_topic?
      current_user&.permission?("forum.topics.lock")
    end

    def can_move_topic?
      current_user&.permission?("forum.topics.move") || current_user&.permission?("forum.topics.lock")
    end

    def can_edit_topic?
      return false unless current_user

      current_user.id == @topic.user_id || current_user.permission?("forum.topics.lock")
    end

    def movable_sections
      Community::Section.ordered.includes(:category).map do |section|
        { slug: section.slug, name: section.name, category: section.category&.name }
      end
    end
  end
end
