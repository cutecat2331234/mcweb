# frozen_string_literal: true

module Commerce
  class CreateProductQuestion < ApplicationService
    def initialize(user:, product:, body:)
      @user = user
      @product = product
      @body = body.to_s.strip
    end

    def call
      return ServiceResult.failure(error: "Question is required.") if @body.blank?

      question = Commerce::ProductQuestion.create!(
        user: @user,
        product: @product,
        body: @body,
        status: "published"
      )
      ServiceResult.success(question)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
