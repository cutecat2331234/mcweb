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
      result = Administration::AbuseRateLimit.call(
        action: :preview,
        account: current_user,
        ip_address: request.remote_ip
      )
      return unless result.failure?

      apply_retry_after_header(result)
      render json: { error: "rate_limited", message: t("mcweb.flash.rate_limited") }, status: :too_many_requests
    end
  end
end
