# frozen_string_literal: true

module Community
  class ModeratePost < ApplicationService
    def initialize(user:, post:, action:, staff_notice: nil, new_username: nil)
      @user = user
      @post = post
      @action = action.to_s
      @staff_notice = staff_notice.to_s.strip.presence
      @new_username = new_username
    end

    def call
      unless @user.permission?("forum.topics.lock")
        return ServiceResult.failure(error: "You are not authorized to moderate this post.")
      end

      case @action
      when "hide"
        @post.update!(status: "hidden")
      when "unhide"
        @post.update!(status: "published")
      when "enable_wiki"
        @post.update!(wiki: true)
      when "disable_wiki"
        @post.update!(wiki: false)
      when "set_staff_notice"
        return ServiceResult.failure(error: "员工提示内容不能为空。") if @staff_notice.blank?

        @post.update!(staff_notice: @staff_notice)
      when "clear_staff_notice"
        @post.update!(staff_notice: nil)
      when "change_author"
        return Community::ChangePostAuthor.call(user: @user, post: @post, new_username: @new_username)
      else
        return ServiceResult.failure(error: "Unknown moderation action.")
      end

      ServiceResult.success(@post)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
