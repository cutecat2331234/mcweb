# frozen_string_literal: true

module Community
  class EditTopic < ApplicationService
    def initialize(user:, topic:, title: nil, tag_names: nil)
      @user = user
      @topic = topic
      @title = title&.strip
      @tag_names = tag_names
    end

    def call
      return ServiceResult.failure(error: "You cannot edit this topic.") unless can_edit?

      Community::Topic.transaction do
        @topic.update!(title: @title) if @title.present?
        if @tag_names
          result = Community::SyncTopicTags.call(topic: @topic, tag_names: @tag_names)
          return result unless result.success?
        end
      end

      ServiceResult.success(@topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def can_edit?
      return false unless @user

      @user.id == @topic.user_id || @user.permission?("forum.topics.lock")
    end
  end
end
