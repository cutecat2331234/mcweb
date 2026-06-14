# frozen_string_literal: true

module Community
  class MarkAllTopicsRead < ApplicationService
    def initialize(user:)
      @user = user
    end

    def call
      Community::ReadState.where(user: @user).find_each do |state|
        max_floor = state.topic.posts.maximum(:floor_number).to_i
        Community::ReadState.mark_read!(@user, state.topic, floor: max_floor)
      end

      ServiceResult.success
    end
  end
end
