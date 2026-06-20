# frozen_string_literal: true

module Community
  class EditTopic < ApplicationService
    def initialize(user:, topic:, title: nil, tag_names: nil, prefix: nil, poll_params: nil)
      @user = user
      @topic = topic
      @title = title&.strip
      @tag_names = tag_names
      @prefix = prefix
      @poll_params = poll_params
    end

    def call
      return ServiceResult.failure(error: "You cannot edit this topic.") unless can_edit?

      Community::Topic.transaction do
        attrs = {}
        attrs[:title] = @title if @title.present?
        attrs[:prefix] = valid_prefix if @prefix != nil
        @topic.update!(attrs) if attrs.any?
        if @tag_names
          result = Community::SyncTopicTags.call(topic: @topic, tag_names: @tag_names, user: @user)
          return result unless result.success?
        end
        if @poll_params
          poll_result = Community::EditTopicPoll.call(user: @user, topic: @topic, **@poll_params)
          return poll_result unless poll_result.success?
        end
      end

      ServiceResult.success(@topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def can_edit?
      Community::SectionModeration.can_edit_topic?(user: @user, topic: @topic)
    end

    def valid_prefix
      return nil if @prefix.blank?

      allowed = @topic.section.prefix_names
      allowed.include?(@prefix) ? @prefix : nil
    end
  end
end
