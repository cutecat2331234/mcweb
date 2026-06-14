# frozen_string_literal: true

module Community
  class PostsController < ApplicationController
    before_action :require_login
    before_action :set_topic, only: :create
    before_action :set_post, only: %i[update destroy]

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
      authorize_post_owner!

      if @post.edit_body!(post_params[:body], editor: current_user)
        redirect_to forum_topic_path(@post.topic), notice: "Post updated."
      else
        redirect_to forum_topic_path(@post.topic), alert: "Unable to update post."
      end
    end

    def destroy
      authorize_post_owner!

      topic = @post.topic
      @post.soft_delete!
      redirect_to forum_topic_path(topic), notice: "Post deleted."
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

    def authorize_post_owner!
      return if current_user&.id == @post.user_id || current_user&.permission?("forum.topics.lock")

      redirect_to forum_topic_path(@post.topic), alert: "You are not authorized to modify this post."
    end
  end
end
