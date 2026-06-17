# frozen_string_literal: true

module Community
  class AnnouncementsController < ApplicationController
    before_action :require_login

    def dismiss
      result = Community::DismissGlobalAnnouncement.call(
        user: current_user,
        topic_public_id: params[:topic_id]
      )

      if result.success?
        head :ok
      else
        render json: { error: result.error }, status: :unprocessable_entity
      end
    end
  end
end
