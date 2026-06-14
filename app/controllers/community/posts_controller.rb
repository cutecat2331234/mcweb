# frozen_string_literal: true

module Community
  class PostsController < ApplicationController
    before_action :require_login, except: %i[raw edits]
    before_action :set_topic, only: :create
    before_action :set_post, only: %i[update destroy toggle_reaction toggle_bookmark moderate edits restore_edit raw restore]

    def create
      result = Community::CreatePost.call(
        user: current_user,
        topic: @topic,
        body: post_params[:body],
        quoted_post: find_quoted_post,
        parent_post: find_parent_post,
        ip_address: request.remote_ip
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
        redirect_to forum_topic_path(@post.topic, anchor: "post-#{@post.id}"), notice: "帖子已更新。"
      else
        redirect_to forum_topic_path(@post.topic), alert: service_error_message(result)
      end
    end

    def destroy
      unless can_delete_post?(@post, current_user)
        return redirect_to forum_topic_path(@post.topic), alert: "无权删除此帖子。"
      end

      topic = @post.topic
      @post.soft_delete!
      Community::SyncTopicLastPost.call(topic: topic)
      redirect_to forum_topic_path(topic), notice: "帖子已删除。"
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
        redirect_to forum_topic_path(@post.topic, anchor: "post-#{@post.id}"), notice: result.value[:bookmarked] ? "已加入书签。" : "已移除书签。"
      else
        redirect_to forum_topic_path(@post.topic), alert: service_error_message(result)
      end
    end

    def moderate
      result = Community::ModeratePost.call(
        user: current_user,
        post: @post,
        action: params[:action_type]
      )

      if result.success?
        redirect_to forum_topic_path(@post.topic, anchor: "post-#{@post.id}"), notice: "帖子已更新。"
      else
        redirect_to forum_topic_path(@post.topic), alert: service_error_message(result)
      end
    end

    def edits
      unless can_view_edits?
        return redirect_to forum_topic_path(@post.topic), alert: "无权查看编辑历史。"
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
        redirect_to forum_topic_path(@post.topic, anchor: "post-#{@post.id}"), notice: "已恢复至选定版本。"
      else
        redirect_to edits_forum_post_path(@post), alert: service_error_message(result)
      end
    end

    def restore
      result = Community::RestorePost.call(actor: current_user, post: @post)

      if result.success?
        redirect_to forum_topic_path(@post.topic, anchor: "post-#{@post.id}"), notice: "帖子已恢复。"
      else
        redirect_to forum_topic_path(@post.topic), alert: service_error_message(result)
      end
    end

    def raw
      return head :not_found unless topic_visible_to_user?(@post.topic)

      render plain: @post.body, content_type: "text/plain; charset=utf-8"
    end

    private

    def set_topic
      topic_id = params[:topic_id].presence || params.dig(:post, :topic_id)
      @topic = Community::Topic.find_by!(public_id: topic_id)
    end

    def set_post
      scope = action_name == "restore" ? Community::Post.with_discarded : Community::Post
      @post = scope.find(params[:id])
    end

    def post_params
      params.require(:post).permit(:body, :quoted_post_id, :parent_post_id, :reason)
    end

    def find_quoted_post
      return if post_params[:quoted_post_id].blank?

      Community::Post.find_by(id: post_params[:quoted_post_id], forum_topic_id: @topic.id)
    end

    def find_parent_post
      return if post_params[:parent_post_id].blank?

      Community::Post.find_by(id: post_params[:parent_post_id], forum_topic_id: @topic.id)
    end

    def can_view_edits?
      return true if @post.topic.wiki?
      return true if current_user&.permission?("forum.topics.lock")
      return true if current_user&.id == @post.user_id

      false
    end

    def topic_visible_to_user?(topic)
      return true unless topic.status == "hidden"
      return true if current_user&.permission?("forum.topics.lock")

      false
    end
  end
end
