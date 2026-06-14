# frozen_string_literal: true

module Community
  class EstimateReadingTime < ApplicationService
    CHARS_PER_MINUTE = 400

    def initialize(topic:)
      @topic = topic
    end

    def call
      text = @topic.posts.where(status: :published).pluck(:body).join(" ")
      minutes = (text.length.to_f / CHARS_PER_MINUTE).ceil
      minutes = 1 if minutes < 1 && text.present?
      ServiceResult.success(minutes: minutes, word_count: text.length)
    end
  end
end
