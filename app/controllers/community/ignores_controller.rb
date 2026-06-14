# frozen_string_literal: true

module Community
  class IgnoresController < ApplicationController
    before_action :require_login

    def create
      result = Community::ToggleUserIgnore.call(
        ignorer: current_user,
        ignored_username: params[:username]
      )

      if result.success?
        redirect_back fallback_location: forum_blocks_path, notice: result.value[:ignored] ? "已忽略该用户。" : "已取消忽略。"
      else
        redirect_back fallback_location: forum_blocks_path, alert: service_error_message(result)
      end
    end
  end
end
