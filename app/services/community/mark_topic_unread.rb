# frozen_string_literal: true

module Community
  class MarkTopicUnread < ApplicationService
    def initialize(user:, topic:)
      @user = user
      @topic = topic
    end

    def call
      state = Community::ReadState.find_or_initialize_by(user: @user, topic: @topic)
      last_floor = @topic.posts.where(status: :published).maximum(:floor_number).to_i
      state.last_read_floor = [ last_floor - 1, 0 ].max
      state.save!
      ServiceResult.success(state)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
