# frozen_string_literal: true

module Community
  class DigestUnsubscribesController < ApplicationController
    def show
      user_id = Community::ForumDigestUnsubscribeToken.verify(params[:token])
      user = User.find(user_id)
      user.update!(forum_digest_frequency: "none")
      redirect_to root_path, notice: t("mcweb.flash.digest_unsubscribed")
    rescue Community::ForumDigestUnsubscribeToken::InvalidToken, ActiveRecord::RecordNotFound
      redirect_to root_path, alert: t("mcweb.flash.digest_unsubscribe_invalid")
    end
  end
end
