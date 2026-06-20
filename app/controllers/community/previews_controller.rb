# frozen_string_literal: true

module Community
  class PreviewsController < ApplicationController
    before_action :require_login
    before_action :rate_limit_preview!, only: :create

    def create
      body = params[:body].to_s
      filtered = Community::FilterCensoredWords.call(text: body)
      body = filtered.success? ? filtered.value : body
      result = Community::FormatPostBody.call(body: body)
      html = result.success? ? result.value : ERB::Util.html_escape(params[:body])

      render json: { html: html }
    end

    private

    def rate_limit_preview!
      result = Administration::RateLimiter.call(
        key: "forum_post_preview:#{current_user.id}:#{request.remote_ip}",
        limit: 30,
        window: 1.minute
      )
      return unless result.failure?

      render json: { error: t("mcweb.flash.rate_limited") }, status: :too_many_requests
    end
  end
end
