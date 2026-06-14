# frozen_string_literal: true

module Community
  class SaveTopicDraft < ApplicationService
    def initialize(user:, section:, title:, body: nil, tag_names: nil, topic: nil)
      @user = user
      @section = section
      @title = title.to_s.strip
      @body = body.to_s.strip
      @tag_names = tag_names
      @topic = topic
    end

    def call
      return ServiceResult.failure(error: "Title is required.") if @title.blank?

      draft = @topic || Community::Topic.new(user: @user, section: @section, status: "draft")

      Community::Topic.transaction do
        draft.assign_attributes(
          title: @title,
          public_id: draft.public_id || "topic_#{SecureRandom.alphanumeric(16)}",
          last_posted_at: Time.current,
          last_post_user: @user,
          replies_count: 0
        )
        draft.save!

        if @body.present?
          post = draft.posts.first_or_initialize(floor_number: 1, user: @user)
          post.assign_attributes(body: @body, status: "published")
          post.save!
        end

        Community::SyncTopicTags.call(topic: draft, tag_names: @tag_names) if @tag_names.present?
      end

      ServiceResult.success(draft)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
