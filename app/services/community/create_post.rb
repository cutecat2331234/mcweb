# frozen_string_literal: true

module Community
  class CreatePost < ApplicationService
    MIN_INTERVAL = 10.seconds
    MIN_BODY_LENGTH = 2

    def initialize(user:, topic:, body:, quoted_post: nil, parent_post: nil, ip_address: nil, skip_interval_check: false)
      @user = user
      @topic = topic
      @body = body.to_s.strip
      filter_censored_body!
      @quoted_post = quoted_post
      @parent_post = parent_post
      @ip_address = ip_address
      @skip_interval_check = skip_interval_check
    end

    def call
      spam_result = check_spam
      return spam_result if spam_result.failure?

      unless @topic.section.allowed?(@user, :reply)
        return ServiceResult.failure(error: "You are not allowed to reply in this section.")
      end

      if @parent_post && @parent_post.forum_topic_id != @topic.id
        return ServiceResult.failure(error: "Invalid parent post.")
      end

      old_trust_level = Community::TrustLevel.level_for(@user)
      post = nil
      @topic.with_lock do
        if @topic.locked?
          return ServiceResult.failure(error: "This topic is locked.")
        end

        floor_number = @topic.posts.maximum(:floor_number).to_i + 1

        post = Community::Post.create!(
          topic: @topic,
          user: @user,
          floor_number: floor_number,
          body: @body,
          quoted_post: @quoted_post,
          parent_post: @parent_post,
          status: "published"
        )
      end

      Community::ReadState.mark_read!(@user, @topic, floor: post.floor_number)
      Community::Subscription.subscribe!(@user, @topic)

      Administration::AuditLogger.call(
        actor: @user,
        action: "community.post_created",
        resource: post,
        ip_address: @ip_address
      )

      Community::NotifyTopicReply.call(post: post)
      Community::ProcessMentions.call(body: @body, author: @user, post: post, topic: @topic)
      Community::NotifyPostQuoted.call(post: post, quoter: @user, quoted_post: @quoted_post) if @quoted_post
      Community::CheckAutoBadges.call(user: @user)
      notify_trust_level_up!(old_trust_level)

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

      if @user.banned?
        return ServiceResult.failure(error: "Your account is banned.")
      end

      ip_result = Administration::CheckIpBan.call(ip_address: @ip_address)
      return ip_result if ip_result.failure?

      if slow_mode_active?
        return ServiceResult.failure(error: "Slow mode is active. Please wait before posting again.")
      end

      recent = Community::Post.where(user: @user).order(created_at: :desc).first
      if !@skip_interval_check && recent && recent.created_at > MIN_INTERVAL.ago
        return ServiceResult.failure(error: "Please wait before posting again.")
      end

      if duplicate_body?
        return ServiceResult.failure(error: "Duplicate post detected.")
      end

      if Community::TrustLevel.contains_link?(@body) && !Community::TrustLevel.can_post_links?(@user)
        return ServiceResult.failure(error: "New members cannot post links. Participate more to unlock this.")
      end

      ServiceResult.success
    end

    def slow_mode_active?
      seconds = @topic.slow_mode_seconds.to_i
      return false if seconds <= 0

      last_in_topic = @topic.posts.where(user: @user).order(created_at: :desc).first
      last_in_topic&.created_at&.> seconds.seconds.ago
    end

    def muted_in_section?
      Community::Mute.muted?(@user, section: @topic.section)
    end

    def duplicate_body?
      Community::Post
        .where(user: @user, forum_topic_id: @topic.id)
        .where("created_at > ?", 5.minutes.ago)
        .where(body: @body)
        .exists?
    end

    def filter_censored_body!
      result = Community::FilterCensoredWords.call(text: @body)
      @body = result.value if result.success?
    end

    def notify_trust_level_up!(old_level)
      info = Community::TrustLevel.level_info(@user)
      return if info[:level] <= old_level

      Community::NotifyTrustLevelUp.call(user: @user, level: info[:level], level_name: info[:name])
    end
  end
end
