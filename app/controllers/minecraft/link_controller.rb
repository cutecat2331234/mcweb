# frozen_string_literal: true

module Minecraft
  class LinkController < ApplicationController
    before_action :require_login

    def show
      render inertia: "Minecraft/Link/Show"
    end

    def create
      result = Minecraft::CompleteLink.call(
        user: current_user,
        code: link_params[:code]
      )

      if result.success?
        redirect_to root_path, notice: t("mcweb.flash.minecraft_linked")
      else
        render inertia: "Minecraft/Link/Show",
               status: :unprocessable_entity,
               props: { form_error: service_error_message(result) }
      end
    end

    private

    def link_params
      params.require(:link).permit(:code)
    end
  end
end
