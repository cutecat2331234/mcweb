# frozen_string_literal: true

module Community
  class CloseScheduledTopic < ApplicationService
    def initialize(topic:)
      @topic = topic
    end

    def call
      return ServiceResult.success if @topic.locked?
      return ServiceResult.success unless @topic.auto_close_at&.<= Time.current

      @topic.update!(locked: true, auto_close_at: nil)
      ServiceResult.success(@topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
