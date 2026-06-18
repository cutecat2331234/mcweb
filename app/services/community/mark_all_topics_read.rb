# frozen_string_literal: true

module Community
  class MarkAllTopicsRead < ApplicationService
    def initialize(user:, topic_ids: nil)
      @user = user
      @topic_ids = topic_ids
    end

    def call
      states = Community::ReadState.where(user: @user)
      states = states.where(forum_topic_id: @topic_ids) if @topic_ids.present?

      states.find_each do |state|
        max_floor = state.topic.posts.maximum(:floor_number).to_i
        Community::ReadState.mark_read!(@user, state.topic, floor: max_floor)
      end

      ServiceResult.success
    end
  end
end
