# frozen_string_literal: true

module Community
  class ScheduleTopic < ApplicationService
    def initialize(user:, section:, title:, body:, scheduled_at:, tag_names: nil, ip_address: nil, prefix: nil, poll_question: nil, poll_options: nil, poll_closes_days: nil, poll_multiple_choice: nil, poll_max_choices: nil, poll_hide_results_until_vote: nil, attachment_ids: nil, custom_fields: nil)
      @user = user
      @section = section
      @title = title.to_s.strip
      @body = body.to_s.strip
      @scheduled_at = scheduled_at
      @tag_names = tag_names
      @ip_address = ip_address
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
      access_result = create_access_result
      return access_result if access_result.failure?

      return ServiceResult.failure(error: :scheduled_time_must_be_in_the_future) unless @scheduled_at > Time.current

      ip_result = Administration::CheckIpBan.call(ip_address: @ip_address)
      return ip_result if ip_result.failure?

      if @section.requires_tags_or_groups? && @tag_names.blank?
        return ServiceResult.failure(error: @section.tag_requirements_message)
      end

      if @section.prefix_required? && @prefix.blank?
        return ServiceResult.failure(error: "section_topic_prefix_required")
      end

      topic = nil
      tag_result = nil
      poll_result = nil
      field_result = nil
      inline_upload_result = nil
      state_result = nil
      lock_attempts = 0
      begin
        Community::Topic.transaction do
          @section = Community::SectionHierarchyLock.lock!(@section).sole
          state_result = create_access_result
          raise ActiveRecord::Rollback if state_result.failure?

          topic = Community::Topic.create!(
            public_id: "topic_#{SecureRandom.alphanumeric(16)}",
            section: @section,
            user: @user,
            title: @title,
            prefix: valid_prefix,
            status: "draft",
            scheduled_at: @scheduled_at,
            last_posted_at: Time.current,
            last_post_user: @user,
            replies_count: 0
          )

          opening_post = Community::Post.create!(
            topic: topic,
            user: @user,
            floor_number: 1,
            body: @body,
            status: "published"
          )
          inline_upload_result = Community::BindInlineUploads.call(
            user: @user,
            post: opening_post,
            body: @body
          )
          raise ActiveRecord::Rollback if inline_upload_result.failure?

          if @tag_names.present?
            tag_result = Community::SyncTopicTags.call(topic: topic, tag_names: @tag_names, user: @user)
            raise ActiveRecord::Rollback unless tag_result.success?
          end

          poll_result = Community::SyncTopicPoll.call(
            topic: topic,
            poll_question: @poll_question,
            poll_options: @poll_options,
            poll_closes_days: @poll_closes_days,
            poll_multiple_choice: @poll_multiple_choice,
            poll_max_choices: @poll_max_choices,
            poll_hide_results_until_vote: @poll_hide_results_until_vote
          )
          raise ActiveRecord::Rollback unless poll_result.success?

          field_result = Community::SyncTopicFieldValues.call(
            topic: topic,
            user: @user,
            values: @custom_fields,
            require_required: true
          )
          raise ActiveRecord::Rollback unless field_result.success?
        end
      rescue Community::SectionHierarchyLock::HierarchyChanged, ActiveRecord::Deadlocked
        lock_attempts += 1
        fresh_section = Community::Section.find_by(id: @section.id)
        if lock_attempts <= 2 && fresh_section
          @section = fresh_section
          retry
        end
        state_result = ServiceResult.failure(error: :section_not_available)
      rescue ActiveRecord::RecordNotFound
        state_result = ServiceResult.failure(error: :section_not_available)
      end

      return state_result if state_result&.failure?
      return tag_result if tag_result&.failure?
      return poll_result if poll_result&.failure?
      return field_result if field_result&.failure?
      return inline_upload_result if inline_upload_result&.failure?

      opening_post = topic.posts.first
      if opening_post
        link_result = Community::LinkPostAttachments.call(user: @user, post: opening_post, attachment_ids: @attachment_ids)
        return link_result if link_result.failure?
      end

      ServiceResult.success(topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def create_access_result
      unless Community::SectionAccess.view?(section: @section, user: @user)
        return ServiceResult.failure(error: :section_not_available)
      end

      unless @section.allowed?(@user, :create_topic)
        return ServiceResult.failure(error: :cannot_create_topic_in_section)
      end

      unless @section.writable_by?(@user, :create_topic)
        return ServiceResult.failure(error: :section_read_only)
      end

      ServiceResult.success
    end

    def valid_prefix
      return nil if @prefix.blank?

      allowed = @section.prefix_names
      allowed.include?(@prefix) ? @prefix : nil
    end
  end
end
