# frozen_string_literal: true

module Community
  class MarkTopicsRead < ApplicationService
    def initialize(user:, topic_public_ids:)
      @user = user
      @topic_public_ids = Array(topic_public_ids).map(&:to_s).uniq
    end

    def call
      return ServiceResult.failure(error: "topics_not_selected") if @topic_public_ids.empty?

      marked = 0
      Community::Topic.where(public_id: @topic_public_ids).find_each do |topic|
        max_floor = topic.posts.countable.maximum(:floor_number).to_i
        Community::ReadState.mark_read!(@user, topic, floor: max_floor)
        marked += 1
      end

      ServiceResult.success(marked: marked)
    end
  end
end
