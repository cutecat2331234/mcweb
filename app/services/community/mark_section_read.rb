# frozen_string_literal: true

module Community
  class MarkSectionRead < ApplicationService
    def initialize(user:, section:)
      @user = user
      @section = section
    end

    def call
      @section.topics.where(status: :published).find_each do |topic|
        max_floor = topic.posts.countable.maximum(:floor_number).to_i
        next if max_floor.zero?

        Community::ReadState.mark_read!(@user, topic, floor: max_floor)
      end

      ServiceResult.success
    end
  end
end
