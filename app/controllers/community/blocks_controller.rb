# frozen_string_literal: true

module Community
  class BlocksController < ApplicationController
    before_action :require_login

    def create
      result = Community::ToggleUserBlock.call(
        blocker: current_user,
        blocked_username: params[:username]
      )

      if result.success?
        redirect_back fallback_location: forum_sections_path, notice: result.value[:blocked] ? "已拉黑该用户。" : "已取消拉黑。"
      else
        redirect_back fallback_location: forum_sections_path, alert: service_error_message(result)
      end
    end
  end
end
