# frozen_string_literal: true

module Community
  class PreviewsController < ApplicationController
    before_action :require_login

    def create
      body = params[:body].to_s
      filtered = Community::FilterCensoredWords.call(text: body)
      body = filtered.success? ? filtered.value : body
      result = Community::FormatPostBody.call(body: body)
      html = result.success? ? result.value : ERB::Util.html_escape(params[:body])

      render json: { html: html }
    end
  end
end
