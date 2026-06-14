# frozen_string_literal: true

module Community
  class CreatePost < ApplicationService
    MIN_INTERVAL = 10.seconds
    MIN_BODY_LENGTH = 2

    def initialize(user:, topic:, body:, quoted_post: nil, ip_address: nil)
      @user = user
      @topic = topic
      @body = body.to_s.strip
      @quoted_post = quoted_post
      @ip_address = ip_address
    end

    def call
      spam_result = check_spam
      return spam_result if spam_result.failure?

      post = nil
      Community::Topic.transaction do
        @topic.lock!

        if @topic.locked?
          return ServiceResult.failure(error: "This topic is locked.")
        end

        floor_number = @topic.forum_posts.maximum(:floor_number).to_i + 1

        post = Community::Post.create!(
          forum_topic: @topic,
          user: @user,
          floor_number: floor_number,
          body: @body,
          quoted_post: @quoted_post,
          status: "published"
        )

        @topic.update!(
          replies_count: @topic.replies_count + 1,
          last_posted_at: Time.current,
          last_post_user: @user
        )
      end

      Administration::AuditLogger.call(
        actor: @user,
        action: "community.post_created",
        resource: post,
        ip_address: @ip_address
      )

      ServiceResult.success(post)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def check_spam
      if @body.length < MIN_BODY_LENGTH
        return ServiceResult.failure(error: "Post body is too short.")
      end

      rate_result = Administration::RateLimiter.call(
        key: "forum_post:#{@user.id}",
        limit: 20,
        window: 1.hour
      )
      return rate_result if rate_result.failure?

      if muted_in_section?
        return ServiceResult.failure(error: "You are muted in this section.")
      end

      recent = Community::Post.where(user: @user).order(created_at: :desc).first
      if recent&.created_at&.> MIN_INTERVAL.ago
        return ServiceResult.failure(error: "Please wait before posting again.")
      end

      if duplicate_body?
        return ServiceResult.failure(error: "Duplicate post detected.")
      end

      ServiceResult.success
    end

    def muted_in_section?
      Community::Mute
        .where(user: @user)
        .where(forum_section: [ @topic.forum_section, nil ])
        .where("expires_at IS NULL OR expires_at > ?", Time.current)
        .exists?
    end

    def duplicate_body?
      Community::Post
        .where(user: @user, forum_topic: @topic)
        .where("created_at > ?", 5.minutes.ago)
        .exists?(body: @body)
    end
  end
end
