# frozen_string_literal: true

module Community
  class UnreadFilterPresetsController < ApplicationController
    before_action :require_login

    def create
      preset = current_user.forum_unread_filter_presets.build(preset_params)
      if preset.save
        head :created
      else
        render json: { error: preset.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end
    end

    def destroy
      preset = current_user.forum_unread_filter_presets.find(params[:id])
      preset.destroy!
      head :no_content
    end

    private

    def preset_params
      params.require(:unread_filter_preset).permit(:name, filters: %i[sort filter section tags tag_match])
    end
  end
end
