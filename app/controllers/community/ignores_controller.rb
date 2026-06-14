# frozen_string_literal: true

module Community
  class IgnoresController < ApplicationController
    before_action :require_login

    def index
      ignores = Community::UserIgnore
        .where(ignorer: current_user)
        .includes(:ignored)
        .order(created_at: :desc)

      render inertia: "Community/Ignores/Index", props: {
        users: ignores.map do |ignore|
          user = ignore.ignored
          {
            username: user.username,
            display_name: user.display_name,
            profile_url: forum_user_path(user.username),
            ignored_at: l(ignore.created_at, format: :short),
            unignore_url: forum_ignore_user_path(user.username)
          }
        end
      }
    end

    def create
      result = Community::ToggleUserIgnore.call(
        ignorer: current_user,
        ignored_username: params[:username]
      )

      if result.success?
        redirect_back fallback_location: forum_ignores_path, notice: result.value[:ignored] ? "已忽略该用户。" : "已取消忽略。"
      else
        redirect_back fallback_location: forum_ignores_path, alert: service_error_message(result)
      end
    end
  end
end
