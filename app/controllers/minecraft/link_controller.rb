# frozen_string_literal: true

module Minecraft
  class LinkController < ApplicationController
    before_action :require_login

    def new
    end

    def create
      result = Minecraft::CompleteLink.call(
        user: current_user,
        code: link_params[:code]
      )

      if result.success?
        redirect_to root_path, notice: "Minecraft account linked successfully."
      else
        flash.now[:alert] = service_error_message(result)
        render :new, status: :unprocessable_entity
      end
    end

    private

    def link_params
      params.expect(link: %i[code])[:link]
    end
  end
end
