# frozen_string_literal: true

module Website
  class RenderArticleBody < ApplicationService
    def initialize(body:)
      @body = body
    end

    def call
      return ServiceResult.success("") if @body.blank?

      Community::FormatPostBody.call(body: @body)
    end
  end
end
