# frozen_string_literal: true

module Community
  class PostsController < ApplicationController
    before_action :require_login
    before_action :set_topic, only: :create
    before_action :set_post, only: %i[update destroy toggle_reaction]

    def create
      result = Community::CreatePost.call(
        user: current_user,
        topic: @topic,
        body: post_params[:body],
        quoted_post: find_quoted_post,
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
        body: post_params[:body]
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
      topic.update!(replies_count: [ topic.posts.count - 1, 0 ].max)
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

    private

    def set_topic
      topic_id = params[:topic_id].presence || params.dig(:post, :topic_id)
      @topic = Community::Topic.find_by!(public_id: topic_id)
    end

    def set_post
      @post = Community::Post.find(params[:id])
    end

    def post_params
      params.require(:post).permit(:body, :quoted_post_id)
    end

    def find_quoted_post
      return if post_params[:quoted_post_id].blank?

      Community::Post.find_by(id: post_params[:quoted_post_id], forum_topic_id: @topic.id)
    end
  end
end
