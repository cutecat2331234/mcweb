# frozen_string_literal: true

module Community
  class ScheduleTopic < ApplicationService
    def initialize(user:, section:, title:, body:, scheduled_at:, tag_names: nil, ip_address: nil, prefix: nil, poll_question: nil, poll_options: nil, poll_closes_days: nil, poll_multiple_choice: nil, poll_max_choices: nil, poll_hide_results_until_vote: nil)
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
    end

    def call
      return ServiceResult.failure(error: "Scheduled time must be in the future.") unless @scheduled_at > Time.current

      ip_result = Administration::CheckIpBan.call(ip_address: @ip_address)
      return ip_result if ip_result.failure?

      unless @section.allowed?(@user, :create_topic)
        return ServiceResult.failure(error: "You are not allowed to create topics in this section.")
      end

      if Array(@section.required_tag_ids).map(&:to_i).reject(&:zero?).any? && @tag_names.blank?
        names = @section.required_tags.pluck(:name).join("、")
        return ServiceResult.failure(error: "此分区要求至少包含以下标签之一：#{names.presence || '指定标签'}")
      end

      if @section.prefix_required? && @prefix.blank?
        return ServiceResult.failure(error: "此分区要求选择主题前缀。")
      end

      topic = nil
      tag_result = nil
      poll_result = nil
      Community::Topic.transaction do
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

        Community::Post.create!(
          topic: topic,
          user: @user,
          floor_number: 1,
          body: @body,
          status: "published"
        )

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
      end

      return tag_result if tag_result&.failure?
      return poll_result if poll_result&.failure?

      ServiceResult.success(topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def valid_prefix
      return nil if @prefix.blank?

      allowed = Array(@section.prefixes)
      allowed.include?(@prefix) ? @prefix : nil
    end
  end
end
