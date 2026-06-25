# frozen_string_literal: true

module Community
  class NoticesController < ApplicationController
    before_action :require_login

    def dismiss
      notice = Community::Notice.find(params[:id])
      ids = Array(current_user.dismissed_forum_notice_ids).map(&:to_s)
      unless ids.include?(notice.id.to_s)
        current_user.update_column(:dismissed_forum_notice_ids, ids + [ notice.id.to_s ])
      end
      head :ok
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end
  end
end
