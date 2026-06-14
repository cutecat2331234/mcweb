# frozen_string_literal: true

module Commerce
  class ShowProductQuestion < ApplicationService
    def initialize(question:)
      @question = question
    end

    def call
      @question.update!(status: :published)
      ServiceResult.success(@question)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
