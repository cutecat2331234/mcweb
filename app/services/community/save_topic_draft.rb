# frozen_string_literal: true

module Community
  class SaveTopicDraft < ApplicationService
    def initialize(user:, section:, title:, body: nil, tag_names: nil, topic: nil, scheduled_at: nil, clear_schedule: false)
      @user = user
      @section = section
      @title = title.to_s.strip
      @body = body.to_s.strip
      @tag_names = tag_names
      @topic = topic
      @scheduled_at = scheduled_at
      @clear_schedule = ActiveModel::Type::Boolean.new.cast(clear_schedule)
    end

    def call
      return ServiceResult.failure(error: "Title is required.") if @title.blank?

      draft = @topic || Community::Topic.new(user: @user, section: @section, status: "draft")
      tag_result = nil

      Community::Topic.transaction do
        draft.assign_attributes(
          title: @title,
          public_id: draft.public_id || "topic_#{SecureRandom.alphanumeric(16)}",
          last_posted_at: Time.current,
          last_post_user: @user,
          replies_count: 0
        )
        apply_schedule!(draft)
        draft.save!

        if @body.present?
          post = draft.posts.first_or_initialize(floor_number: 1, user: @user)
          post.assign_attributes(body: @body, status: "published")
          post.save!
        end

        if @tag_names.present?
          tag_result = Community::SyncTopicTags.call(topic: draft, tag_names: @tag_names, user: @user)
          raise ActiveRecord::Rollback unless tag_result.success?
        end
      end

      return tag_result if tag_result&.failure?

      ServiceResult.success(draft)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def apply_schedule!(draft)
      if @clear_schedule
        draft.scheduled_at = nil
        return
      end

      return if @scheduled_at.nil?

      parsed = Time.zone.parse(@scheduled_at.to_s) rescue nil
      if @scheduled_at.to_s.blank?
        draft.scheduled_at = nil
      elsif parsed&.> Time.current
        draft.scheduled_at = parsed
      end
    end
  end
end
