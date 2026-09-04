# frozen_string_literal: true

module Community
  class SaveTopicDraft < ApplicationService
    NOT_PROVIDED = Object.new.freeze

    def initialize(user:, section:, title:, body: nil, tag_names: nil, topic: nil, scheduled_at: nil, clear_schedule: false, prefix: nil, poll_question: nil, poll_options: nil, poll_closes_days: nil, poll_multiple_choice: nil, poll_max_choices: nil, poll_hide_results_until_vote: nil, attachment_ids: nil, custom_fields: NOT_PROVIDED)
      @user = user
      @section = section
      @title = title.to_s.strip
      @body = body.to_s.strip
      @tag_names = tag_names
      @topic = topic
      @scheduled_at = scheduled_at
      @clear_schedule = ActiveModel::Type::Boolean.new.cast(clear_schedule)
      @prefix = prefix.to_s.strip.presence
      @poll_question = poll_question
      @poll_options = poll_options
      @poll_closes_days = poll_closes_days
      @poll_multiple_choice = poll_multiple_choice
      @poll_max_choices = poll_max_choices
      @poll_hide_results_until_vote = poll_hide_results_until_vote
      @attachment_ids = attachment_ids
      @custom_fields = custom_fields
    end

    def call
      unless Community::SectionAccess.view?(section: @section, user: @user)
        return ServiceResult.failure(error: :section_not_available)
      end

      if @topic && !Community::ForumAccess.topic_visible?(topic: @topic, user: @user)
        return ServiceResult.failure(error: :topic_not_available)
      end

      return ServiceResult.failure(error: :title_required) if @title.blank?

      if @section.requires_tags_or_groups? && @tag_names.blank?
        return ServiceResult.failure(error: @section.tag_requirements_message)
      end

      draft = @topic || Community::Topic.new(user: @user, section: @section, status: "draft")
      tag_result = nil
      poll_result = nil
      field_result = nil
      inline_upload_result = nil
      link_result = nil
      state_result = nil

      Community::Topic.transaction do
        @user = User.lock.find(@user.id)
        state_result = account_write_access_result
        raise ActiveRecord::Rollback if state_result.failure?

        if draft.persisted?
          draft.lock!
          unless draft.user_id == @user.id && draft.status == "draft"
            state_result = ServiceResult.failure(error: :topic_is_not_a_draft)
            raise ActiveRecord::Rollback
          end
        end
        draft.user = @user
        draft.assign_attributes(
          title: @title,
          prefix: valid_prefix,
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
          inline_upload_result = Community::BindInlineUploads.call(
            user: @user,
            post: post,
            body: @body
          )
          raise ActiveRecord::Rollback if inline_upload_result.failure?
        end

        if @tag_names.present?
          tag_result = Community::SyncTopicTags.call(topic: draft, tag_names: @tag_names, user: @user)
          raise ActiveRecord::Rollback unless tag_result.success?
        end

        poll_result = Community::SyncTopicPoll.call(
          topic: draft,
          poll_question: @poll_question,
          poll_options: @poll_options,
          poll_closes_days: @poll_closes_days,
          poll_multiple_choice: @poll_multiple_choice,
          poll_max_choices: @poll_max_choices,
          poll_hide_results_until_vote: @poll_hide_results_until_vote
        )
        raise ActiveRecord::Rollback unless poll_result.success?

        unless @custom_fields.equal?(NOT_PROVIDED)
          field_result = Community::SyncTopicFieldValues.call(
            topic: draft,
            user: @user,
            values: @custom_fields,
            require_required: false
          )
          raise ActiveRecord::Rollback unless field_result.success?
        end

        opening_post = draft.posts.first
        if opening_post
          link_result = Community::LinkPostAttachments.call(
            user: @user,
            post: opening_post,
            attachment_ids: @attachment_ids
          )
          raise ActiveRecord::Rollback if link_result.failure?
        end
      end

      return state_result if state_result&.failure?
      return tag_result if tag_result&.failure?
      return poll_result if poll_result&.failure?
      return field_result if field_result&.failure?
      return inline_upload_result if inline_upload_result&.failure?
      return link_result if link_result&.failure?

      ServiceResult.success(draft)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def account_write_access_result
      return ServiceResult.failure(error: :account_deleted) if @user.deleted?
      return ServiceResult.failure(error: :account_banned) if @user.banned?

      ServiceResult.success
    end

    def valid_prefix
      return nil if @prefix.blank?

      allowed = @section.prefix_names
      allowed.include?(@prefix) ? @prefix : nil
    end

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
