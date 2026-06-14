# frozen_string_literal: true

module Community
  class TopicsController < ApplicationController
    include Community::TopicVisibility

    before_action :require_login, only: %i[new create update toggle_subscription toggle_bookmark moderate move merge mark_solved unsolve update_slow_mode update_auto_close mark_unread]
    before_action :set_section, only: %i[new create]
    before_action :set_topic, only: %i[show update toggle_subscription toggle_bookmark moderate move merge mark_solved unsolve update_slow_mode update_auto_close mark_unread]

    def show
      @topic.record_view!
      mark_topic_notifications_read!

      posts_scope = @topic.posts.chronological.includes(:user, :quoted_post, :parent_post, :reactions, :edits)
      posts_scope = filter_blocked_posts(posts_scope)

      per_page = 20
      target_post_id = params[:post_id].presence || params[:anchor].to_s.sub(/\Apost-/, "").presence
      target_page = resolve_post_page(posts_scope, target_post_id, per_page: per_page)
      first_unread_floor = logged_in? ? Community::ReadState.first_unread_floor(current_user, @topic) : nil
      if params[:unread] == "1" && first_unread_floor
        target_page = Community::ReadState.page_for_floor(first_unread_floor, per_page: per_page)
      end

      @pagy, posts = pagy(posts_scope, limit: per_page, page: target_page)
      mark_topic_read!(posts) unless params[:unread] == "1"
      last_read_floor = logged_in? ? Community::ReadState.find_by(user: current_user, topic: @topic)&.last_read_floor.to_i : 0

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
        lastReadFloor: last_read_floor,
        firstUnreadFloor: first_unread_floor,
        markUnreadUrl: logged_in? ? mark_unread_forum_topic_path(@topic) : nil,
        jumpToUnreadUrl: first_unread_floor ? forum_topic_path(@topic, unread: 1) : nil,
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
      unless @section.allowed?(current_user, :create_topic)
        return redirect_to forum_section_path(@section), alert: "你无权在此分区发帖。"
      end

      render inertia: "Community/Topics/New", props: {
        section: section_props
      }
    end

    def create
      if topic_params[:scheduled_at].present?
        scheduled_at = Time.zone.parse(topic_params[:scheduled_at].to_s) rescue nil
        if scheduled_at&.> Time.current
          result = Community::ScheduleTopic.call(
            user: current_user,
            section: @section,
            title: topic_params[:title],
            body: topic_params[:body],
            scheduled_at: scheduled_at,
            tag_names: topic_params[:tags],
            prefix: topic_params[:prefix],
            ip_address: request.remote_ip
          )
          if result.success?
            return redirect_to forum_drafts_path, notice: "主题已定时，将于 #{l(scheduled_at, format: :short)} 发布。"
          end
          return render inertia: "Community/Topics/New",
                        props: { section: section_props },
                        status: :unprocessable_entity,
                        errors: topic_errors(result)
        end
      end

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
                 section: section_props
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

    def update_auto_close
      return redirect_to forum_topic_path(@topic), alert: "无权操作。" unless can_moderate_topic?

      at = params[:auto_close_at].present? ? Time.zone.parse(params[:auto_close_at].to_s) : nil
      @topic.update!(auto_close_at: at)
      redirect_to forum_topic_path(@topic), notice: at ? "主题将于 #{l(at, format: :short)} 自动关闭。" : "自动关闭已取消。"
    rescue ArgumentError
      redirect_to forum_topic_path(@topic), alert: "无效的关闭时间。"
    end

    def mark_unread
      result = Community::MarkTopicUnread.call(user: current_user, topic: @topic)

      if result.success?
        redirect_to forum_topic_path(@topic), notice: "已标记为未读。"
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
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
      params.require(:topic).permit(:title, :body, :tags, :poll_question, :poll_options, :poll_closes_days, :prefix, :scheduled_at)
    end

    def section_props
      {
        name: @section.name,
        slug: @section.slug,
        url: forum_section_path(@section),
        prefixes: Array(@section.prefixes)
      }
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

    def mark_topic_read!(posts)
      return unless logged_in?
      return if posts.blank?

      last_floor = posts.map(&:floor_number).max.to_i
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

      types = %w[forum.topic_reply forum.mention forum.section_topic forum.reaction forum.tag_topic forum.followed_topic forum.quote forum.topic_solved]
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

    def resolve_post_page(posts_scope, post_id, per_page:)
      return params[:page].to_i if params[:page].present? && params[:page].to_i.positive?
      return 1 if post_id.blank?

      post = posts_scope.find_by(id: post_id)
      return 1 unless post

      Community::ReadState.page_for_floor(post.floor_number, per_page: per_page)
    end
  end
end
