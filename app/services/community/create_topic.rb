# frozen_string_literal: true

module Community
  class CreateTopic < ApplicationService
    MIN_INTERVAL = 30.seconds
    MIN_BODY_LENGTH = 2

    def initialize(user:, section:, title:, body:, tag_names: nil, ip_address: nil, poll_question: nil, poll_options: nil, poll_closes_days: nil, poll_multiple_choice: nil, poll_max_choices: nil, poll_hide_results_until_vote: nil, prefix: nil)
      @user = user
      @section = section
      @title = title.to_s.strip
      @body = body.to_s.strip
      filter_censored_body!
      @tag_names = tag_names
      @ip_address = ip_address
      @poll_question = poll_question.to_s.strip.presence
      @poll_options = Array(poll_options).map(&:to_s).map(&:strip).reject(&:blank?)
      @poll_closes_days = poll_closes_days.to_i
      @poll_multiple_choice = ActiveModel::Type::Boolean.new.cast(poll_multiple_choice) || false
      @poll_max_choices = [ poll_max_choices.to_i, 1 ].max
      @poll_hide_results_until_vote = ActiveModel::Type::Boolean.new.cast(poll_hide_results_until_vote) || false
      @prefix = prefix.to_s.strip.presence
    end

    def call
      spam_result = check_spam
      return spam_result if spam_result.failure?

      unless @section.allowed?(@user, :create_topic)
        return ServiceResult.failure(error: "You are not allowed to create topics in this section.")
      end

      topic = nil
      tag_result = nil
      Community::Topic.transaction do
        topic = Community::Topic.create!(
          public_id: generate_public_id,
          section: @section,
          user: @user,
          title: @title,
          prefix: valid_prefix,
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
        if @tag_names.present?
          tag_result = Community::SyncTopicTags.call(topic: topic, tag_names: @tag_names, user: @user)
          raise ActiveRecord::Rollback unless tag_result.success?
        end
        create_poll!(topic) if @poll_question && @poll_options.size >= 2
      end

      return tag_result if tag_result&.failure?

      Administration::AuditLogger.call(
        actor: @user,
        action: "community.topic_created",
        resource: topic,
        ip_address: @ip_address
      )

      opening_post = topic.posts.first
      Community::ProcessMentions.call(body: @body, author: @user, post: opening_post, topic: topic) if opening_post
      Community::NotifySectionTopic.call(topic: topic)
      Community::NotifyFollowedUserTopic.call(topic: topic)
      if @tag_names.present? && topic.tags.any?
        Community::NotifyTagTopic.call(topic: topic, tags: topic.tags)
      end
      Community::CheckAutoBadges.call(user: @user)

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

      if section_requires_tags? && @tag_names.blank?
        return ServiceResult.failure(error: required_tags_message)
      end

      if @section.prefix_required? && @prefix.blank?
        return ServiceResult.failure(error: "此分区要求选择主题前缀。")
      end

      if @user.banned?
        return ServiceResult.failure(error: "Your account is banned.")
      end

      ip_result = Administration::CheckIpBan.call(ip_address: @ip_address)
      return ip_result if ip_result.failure?

      recent = Community::Topic.where(user: @user).order(created_at: :desc).first
      if recent&.created_at&.> MIN_INTERVAL.ago
        return ServiceResult.failure(error: "Please wait before creating another topic.")
      end

      if duplicate_title?
        return ServiceResult.failure(error: "A similar topic was recently created.")
      end

      if Community::TrustLevel.contains_link?(@body) && !Community::TrustLevel.can_post_links?(@user)
        return ServiceResult.failure(error: "New members cannot post links. Participate more to unlock this.")
      end

      ServiceResult.success
    end

    def muted_in_section?
      Community::Mute.muted?(@user, section: @section)
    end

    def section_requires_tags?
      Array(@section.required_tag_ids).map(&:to_i).reject(&:zero?).any?
    end

    def required_tags_message
      names = @section.required_tags.pluck(:name).join("、")
      "此分区要求至少包含以下标签之一：#{names.presence || '指定标签'}"
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

    def valid_prefix
      return nil if @prefix.blank?

      allowed = Array(@section.prefixes)
      allowed.include?(@prefix) ? @prefix : nil
    end

    def create_poll!(topic)
      closes_at = @poll_closes_days.positive? ? @poll_closes_days.days.from_now : nil
      max_choices = @poll_multiple_choice ? [ @poll_max_choices, @poll_options.size ].min : 1
      Community::Poll.create!(
        topic: topic,
        question: @poll_question,
        options: @poll_options.first(10),
        closes_at: closes_at,
        multiple_choice: @poll_multiple_choice,
        max_choices: max_choices,
        hide_results_until_vote: @poll_hide_results_until_vote
      )
    end

    def filter_censored_body!
      result = Community::FilterCensoredWords.call(text: @body)
      @body = result.value if result.success?
    end
  end
end
