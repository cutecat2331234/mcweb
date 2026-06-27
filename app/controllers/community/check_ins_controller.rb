# frozen_string_literal: true

module Community
  class CheckInsController < ApplicationController
    before_action :require_login

    def create
      result = Community::DailyCheckIn.call(user: current_user)

      if result.success?
        value = result.value
        flash[:notice] = if value[:already_checked]
          t("mcweb.forum.check_in.already")
        else
          t("mcweb.forum.check_in.success", points: value[:points_awarded], streak: value[:streak])
        end
      else
        flash[:alert] = service_error_message(result)
      end

      redirect_back(fallback_location: forum_path)
    end
  end
end
