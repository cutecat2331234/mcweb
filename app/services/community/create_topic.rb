# frozen_string_literal: true

module Community
  class CreateTopic < ApplicationService
    MIN_INTERVAL = 30.seconds
    MIN_BODY_LENGTH = 2

    def initialize(user:, section:, title:, body:, ip_address: nil)
      @user = user
      @section = section
      @title = title.to_s.strip
      @body = body.to_s.strip
      @ip_address = ip_address
    end

    def call
      spam_result = check_spam
      return spam_result if spam_result.failure?

      unless @section.allowed?(@user, :create_topic)
        return ServiceResult.failure(error: "You are not allowed to create topics in this section.")
      end

      topic = nil
      Community::Topic.transaction do
        topic = Community::Topic.create!(
          public_id: generate_public_id,
          section: @section,
          user: @user,
          title: @title,
          status: "published",
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

        Community::Subscription.subscribe!(@user, topic)
        Community::ReadState.mark_read!(@user, topic, floor: 1)
      end

      Administration::AuditLogger.call(
        actor: @user,
        action: "community.topic_created",
        resource: topic,
        ip_address: @ip_address
      )

      ServiceResult.success(topic)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def check_spam
      if @title.blank?
        return ServiceResult.failure(error: "Title is required.")
      end

      if @body.length < MIN_BODY_LENGTH
        return ServiceResult.failure(error: "Post body is too short.")
      end

      rate_result = Administration::RateLimiter.call(
        key: "forum_topic:#{@user.id}",
        limit: 5,
        window: 1.hour
      )
      return rate_result if rate_result.failure?

      if muted_in_section?
        return ServiceResult.failure(error: "You are muted in this section.")
      end

      if @user.banned?
        return ServiceResult.failure(error: "Your account is banned.")
      end

      recent = Community::Topic.where(user: @user).order(created_at: :desc).first
      if recent&.created_at&.> MIN_INTERVAL.ago
        return ServiceResult.failure(error: "Please wait before creating another topic.")
      end

      if duplicate_title?
        return ServiceResult.failure(error: "A similar topic was recently created.")
      end

      ServiceResult.success
    end

    def muted_in_section?
      Community::Mute.muted?(@user, section: @section)
    end

    def duplicate_title?
      Community::Topic
        .where(user: @user, forum_section_id: @section.id)
        .where("created_at > ?", 1.hour.ago)
        .where("LOWER(title) = ?", @title.downcase)
        .exists?
    end

    def generate_public_id
      "topic_#{SecureRandom.alphanumeric(16)}"
    end
  end
end
