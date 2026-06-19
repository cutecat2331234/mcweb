# frozen_string_literal: true

module Community
  class PostsController < ApplicationController
    include Community::TopicVisibility

    before_action :require_login, except: %i[raw edits]
    before_action :set_topic, only: :create
    before_action :set_post, only: %i[update destroy toggle_reaction toggle_bookmark moderate edits restore_edit raw restore fork_topic]

    def create
      result = Community::CreatePost.call(
        user: current_user,
        topic: @topic,
        body: post_params[:body],
        quoted_post: find_quoted_post,
        parent_post: find_parent_post,
        ip_address: request.remote_ip,
        whisper: post_params[:whisper] == "1" || post_params[:whisper] == true
      )

      if result.success?
        redirect_to forum_topic_path(@topic, anchor: "post-#{result.value.id}")
      else
        redirect_to forum_topic_path(@topic), alert: service_error_message(result)
      end
    end

    def update
      result = Community::EditPost.call(
        user: current_user,
        post: @post,
        body: post_params[:body],
        reason: post_params[:reason]
      )

      if result.success?
        redirect_to forum_topic_path(@post.topic, anchor: "post-#{@post.id}"), notice: t("mcweb.flash.post_updated")
      else
        redirect_to forum_topic_path(@post.topic), alert: service_error_message(result)
      end
    end

    def destroy
      unless PollParticipation.visible?(topic: @post.topic, user: current_user)
        return redirect_to root_path, alert: t("mcweb.flash.topic_unavailable")
      end

      unless can_delete_post?(@post, current_user)
        return redirect_to forum_topic_path(@post.topic), alert: t("mcweb.flash.cannot_delete_post")
      end

      topic = @post.topic
      @post.soft_delete!
      Community::SyncTopicLastPost.call(topic: topic)
      redirect_to forum_topic_path(topic), notice: t("mcweb.flash.post_deleted")
    end

    def toggle_reaction
      result = Community::ToggleReaction.call(
        user: current_user,
        post: @post,
        emoji: params[:emoji]
      )

      if result.success?
        redirect_to forum_topic_path(@post.topic, anchor: "post-#{@post.id}")
      else
        redirect_to forum_topic_path(@post.topic), alert: service_error_message(result)
      end
    end

    def toggle_bookmark
      result = Community::TogglePostBookmark.call(user: current_user, post: @post)

      if result.success?
        redirect_to forum_topic_path(@post.topic, anchor: "post-#{@post.id}"), notice: result.value[:bookmarked] ? t("mcweb.flash.bookmark_added") : t("mcweb.flash.bookmark_removed")
      else
        redirect_to forum_topic_path(@post.topic), alert: service_error_message(result)
      end
    end

    def moderate
      result = Community::ModeratePost.call(
        user: current_user,
        post: @post,
        action: params[:action_type],
        staff_notice: params[:staff_notice],
        new_username: params[:new_username]
      )

      if result.success?
        redirect_to forum_topic_path(@post.topic, anchor: "post-#{@post.id}"), notice: t("mcweb.flash.post_updated")
      else
        redirect_to forum_topic_path(@post.topic), alert: service_error_message(result)
      end
    end

    def edits
      return head :not_found unless PostAccess.readable?(post: @post, user: current_user)

      unless can_view_edits?
        return redirect_to forum_topic_path(@post.topic), alert: t("mcweb.flash.cannot_view_edit_history")
      end

      edits = @post.edits.includes(:editor).order(created_at: :desc)

      render inertia: "Community/Posts/Edits", props: {
        post: {
          id: @post.id,
          floor_number: @post.floor_number,
          topic_url: forum_topic_path(@post.topic)
        },
        edits: edits.map do |edit|
          diff = Community::DiffLines.call(before_text: edit.body_before, after_text: edit.body_after)
          {
            id: edit.id,
            editor: edit.editor.username,
            body_before: edit.body_before,
            body_after: edit.body_after,
            diff_lines: diff.success? ? diff.value : [],
            reason: edit.reason,
            created_at: l(edit.created_at, format: :short),
            restore_url: can_view_edits? ? restore_edit_forum_post_path(@post, edit_id: edit.id) : nil
          }
        end,
        can_restore: can_view_edits?
      }
    end

    def restore_edit
      edit = @post.edits.find(params[:edit_id])
      result = Community::RestorePostEdit.call(user: current_user, edit: edit)

      if result.success?
        redirect_to forum_topic_path(@post.topic, anchor: "post-#{@post.id}"), notice: t("mcweb.flash.post_restored_version")
      else
        redirect_to edits_forum_post_path(@post), alert: service_error_message(result)
      end
    end

    def restore
      result = Community::RestorePost.call(actor: current_user, post: @post)

      if result.success?
        redirect_to forum_topic_path(@post.topic, anchor: "post-#{@post.id}"), notice: t("mcweb.flash.post_restored")
      else
        redirect_to forum_topic_path(@post.topic), alert: service_error_message(result)
      end
    end

    def fork_topic
      section = params[:section_slug].present? ? Community::Section.find_by(slug: params[:section_slug]) : nil
      result = Community::CreateTopicFromPost.call(
        user: current_user,
        post: @post,
        title: params[:title],
        body: params[:body],
        section: section,
        ip_address: request.remote_ip
      )

      if result.success?
        redirect_to forum_topic_path(result.value), notice: t("mcweb.flash.topic_created_from_post")
      else
        redirect_to forum_topic_path(@post.topic, anchor: "post-#{@post.id}"), alert: service_error_message(result)
      end
    end

    def raw
      return head :not_found unless PostAccess.readable?(post: @post, user: current_user)

      render plain: @post.body, content_type: "text/plain; charset=utf-8"
    end

    private

    def set_topic
      topic_id = params[:topic_id].presence || params.dig(:post, :topic_id)
      @topic = Community::Topic.find_by!(public_id: topic_id)
      ensure_topic_visible!(@topic)
    end

    def set_post
      scope = action_name == "restore" ? Community::Post.with_discarded : Community::Post
      @post = scope.find(params[:id])
    end

    def post_params
      params.require(:post).permit(:body, :quoted_post_id, :parent_post_id, :reason, :whisper)
    end

    def find_quoted_post
      return if post_params[:quoted_post_id].blank?

      post = Community::Post.find_by(id: post_params[:quoted_post_id], forum_topic_id: @topic.id)
      post if post && PostAccess.readable?(post: post, user: current_user)
    end

    def find_parent_post
      return if post_params[:parent_post_id].blank?

      post = Community::Post.find_by(id: post_params[:parent_post_id], forum_topic_id: @topic.id)
      post if post && PostAccess.readable?(post: post, user: current_user)
    end

    def can_view_edits?
      return true if @post.topic.wiki?
      return true if current_user&.permission?("forum.topics.lock")
      return true if current_user&.id == @post.user_id

      false
    end
  end
end
