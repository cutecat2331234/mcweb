# frozen_string_literal: true

module Community
  class DigestUnsubscribesController < ApplicationController
    def show
      user_id = Community::ForumDigestUnsubscribeToken.verify(params[:token])
      user = User.find(user_id)
      user.update!(forum_digest_frequency: "none")
      redirect_to forum_preferences_path, notice: "已关闭论坛邮件摘要。"
    rescue Community::ForumDigestUnsubscribeToken::InvalidToken, ActiveRecord::RecordNotFound
      redirect_to forum_preferences_path, alert: "取消摘要链接无效或已过期。"
    end
  end
end
