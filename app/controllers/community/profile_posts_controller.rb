# frozen_string_literal: true

module Community
  class ProfilePostsController < ApplicationController
    before_action :require_login

    def create
      profile_user = User.active.find_by!(username: params[:username])
      result = Community::CreateProfilePost.call(
        author: current_user,
        profile_user: profile_user,
        body: params.dig(:profile_post, :body)
      )

      if result.success?
        redirect_to forum_user_path(profile_user.username), notice: t("mcweb.flash.profile_post_created", default: "留言已发布")
      else
        redirect_to forum_user_path(profile_user.username), alert: service_error_message(result)
      end
    end

    def destroy
      post = Community::ProfilePost.find(params[:id])
      return head :forbidden unless can_manage?(post)

      post.soft_delete!
      redirect_to forum_user_path(post.profile_user.username), notice: t("mcweb.flash.profile_post_deleted", default: "留言已删除")
    end

    private

    def can_manage?(post)
      post.user_id == current_user.id ||
        post.profile_user_id == current_user.id ||
        current_user.permission?("forum.topics.lock") ||
        current_user.permission?("admin.access")
    end
  end
end
