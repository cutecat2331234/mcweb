# frozen_string_literal: true

module Community
  class ProfilePostCommentsController < ApplicationController
    before_action :require_login

    def create
      post = Community::ProfilePost.find(params[:profile_post_id])
      result = Community::CreateProfilePostComment.call(
        author: current_user,
        profile_post: post,
        body: params.dig(:comment, :body)
      )
      username = post.profile_user.username

      if result.success?
        redirect_to forum_user_path(username), notice: t("mcweb.flash.profile_post_comment_created", default: "评论已发布")
      else
        redirect_to forum_user_path(username), alert: service_error_message(result)
      end
    end

    def destroy
      comment = Community::ProfilePostComment.find(params[:id])
      return head :forbidden unless can_manage?(comment)

      username = comment.profile_post.profile_user.username
      comment.soft_delete!
      redirect_to forum_user_path(username), notice: t("mcweb.flash.profile_post_comment_deleted", default: "评论已删除")
    end

    private

    def can_manage?(comment)
      comment.user_id == current_user.id ||
        comment.profile_post.profile_user_id == current_user.id ||
        current_user.permission?("forum.topics.lock") ||
        current_user.permission?("admin.access")
    end
  end
end
