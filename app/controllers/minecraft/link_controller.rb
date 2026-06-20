# frozen_string_literal: true

module Minecraft
  class LinkController < ApplicationController
    before_action :require_login
    before_action :rate_limit_link_attempts!, only: :create

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

    def rate_limit_link_attempts!
      result = Administration::RateLimiter.call(
        key: "minecraft_link:#{current_user.id}:#{request.remote_ip}",
        limit: 10,
        window: 15.minutes
      )
      return unless result.failure?

      render inertia: "Minecraft/Link/Show",
             status: :too_many_requests,
             props: { form_error: t("mcweb.flash.rate_limited", default: "操作过于频繁，请稍后再试。") }
    end
  end
end
