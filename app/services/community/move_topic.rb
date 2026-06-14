# frozen_string_literal: true

module Community
  class MoveTopic < ApplicationService
    def initialize(user:, topic:, section:)
      @user = user
      @topic = topic
      @section = section
    end

    def call
      unless @user.permission?("forum.topics.move") || @user.permission?("forum.topics.lock")
        return ServiceResult.failure(error: "You are not authorized to move this topic.")
      end

      return ServiceResult.failure(error: "Topic is already in this section.") if @topic.forum_section_id == @section.id

      @topic.update!(section: @section)
      ServiceResult.success(@topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
