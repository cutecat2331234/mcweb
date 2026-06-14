# frozen_string_literal: true

module Community
  class CreateTopic < ApplicationService
    MIN_INTERVAL = 30.seconds

    def initialize(user:, section:, title:, ip_address: nil)
      @user = user
      @section = section
      @title = title.to_s.strip
      @ip_address = ip_address
    end

    def call
      spam_result = check_spam
      return spam_result if spam_result.failure?

      topic = Community::Topic.create!(
        public_id: generate_public_id,
        forum_section: @section,
        user: @user,
        title: @title,
        status: "published",
        last_posted_at: Time.current,
        last_post_user: @user
      )

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
      rate_result = Administration::RateLimiter.call(
        key: "forum_topic:#{@user.id}",
        limit: 5,
        window: 1.hour
      )
      return rate_result if rate_result.failure?

      if muted_in_section?
        return ServiceResult.failure(error: "You are muted in this section.")
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
      Community::Mute
        .where(user: @user)
        .where(forum_section: [ @section, nil ])
        .where("expires_at IS NULL OR expires_at > ?", Time.current)
        .exists?
    end

    def duplicate_title?
      Community::Topic
        .where(user: @user, forum_section: @section)
        .where("created_at > ?", 1.hour.ago)
        .where("LOWER(title) = ?", @title.downcase)
        .exists?
    end

    def generate_public_id
      "topic_#{SecureRandom.alphanumeric(16)}"
    end
  end
end
