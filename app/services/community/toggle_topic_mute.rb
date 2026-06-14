# frozen_string_literal: true

module Community
  class ToggleTopicMute < ApplicationService
    def initialize(user:, topic:)
      @user = user
      @topic = topic
    end

    def call
      mute = Community::TopicMute.find_by(user: @user, topic: @topic)
      if mute
        mute.destroy!
        ServiceResult.success(muted: false)
      else
        Community::TopicMute.create!(user: @user, topic: @topic)
        ServiceResult.success(muted: true)
      end
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
