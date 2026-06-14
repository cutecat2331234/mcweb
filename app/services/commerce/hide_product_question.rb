# frozen_string_literal: true

module Commerce
  class HideProductQuestion < ApplicationService
    def initialize(question:)
      @question = question
    end

    def call
      @question.update!(status: :hidden)
      ServiceResult.success(@question)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
