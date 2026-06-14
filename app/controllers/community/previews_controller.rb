# frozen_string_literal: true

module Community
  class PreviewsController < ApplicationController
    before_action :require_login

    def create
      result = Community::FormatPostBody.call(body: params[:body].to_s)
      html = result.success? ? result.value : ERB::Util.html_escape(params[:body])

      render json: { html: html }
    end
  end
end
