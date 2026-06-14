# frozen_string_literal: true

module Community
  class ScheduleTopic < ApplicationService
    def initialize(user:, section:, title:, body:, scheduled_at:, tag_names: nil, ip_address: nil, prefix: nil)
      @user = user
      @section = section
      @title = title.to_s.strip
      @body = body.to_s.strip
      @scheduled_at = scheduled_at
      @tag_names = tag_names
      @ip_address = ip_address
      @prefix = prefix.to_s.strip.presence
    end

    def call
      return ServiceResult.failure(error: "Scheduled time must be in the future.") unless @scheduled_at > Time.current

      ip_result = Administration::CheckIpBan.call(ip_address: @ip_address)
      return ip_result if ip_result.failure?

      unless @section.allowed?(@user, :create_topic)
        return ServiceResult.failure(error: "You are not allowed to create topics in this section.")
      end

      topic = nil
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

        Community::SyncTopicTags.call(topic: topic, tag_names: @tag_names) if @tag_names.present?
      end

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
