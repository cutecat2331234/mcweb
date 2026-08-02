# frozen_string_literal: true

module Community
  class CreatePost < ApplicationService
    MIN_INTERVAL = 10.seconds
    MIN_BODY_LENGTH = 2

    def initialize(user:, topic:, body:, quoted_post: nil, parent_post: nil, ip_address: nil, skip_interval_check: false, whisper: false, attachment_ids: nil, idempotency_key: nil)
      @user = user
      @topic = topic
      @body = body.to_s.strip
      @quoted_post = quoted_post
      @parent_post = parent_post
      @ip_address = ip_address
      @skip_interval_check = skip_interval_check
      @whisper = ActiveModel::Type::Boolean.new.cast(whisper)
      @attachment_ids = attachment_ids
      @idempotency_key = idempotency_key
      apply_plugin_filters!
      filter_censored_body!
    end

    def call
      return call_core unless plugin_service_decorators_available?

      Mcweb::Plugins.call_service(
        "forum.post.create",
        input: plugin_attributes,
        context: { user: @user, topic: @topic }
      ) do |input, _context|
        apply_plugin_attributes!(input)
        call_core
      end
    end

    def call_core
      access_result = reply_access_result
      return access_result if access_result.failure?

      rate_result = enforce_rate_limit
      return rate_result if rate_result.failure?

      old_trust_level = Community::TrustLevel.level_for(@user)
      needs_approval = Community::RequiresPostApproval.required_for?(user: @user, whisper: @whisper)
      post_status = needs_approval ? "pending_approval" : "published"
      post = nil
      attachment_result = nil
      inline_upload_result = nil
      request_result = nil
      spam_result = nil
      state_result = nil
      replayed = false
      section_lock_attempts = 0
      begin
        Community::Post.transaction do
          @topic, = Community::SectionHierarchyLock.lock_topic!(@topic)
          state_result = reply_access_result
          raise ActiveRecord::Rollback if state_result.failure?

          request_result = Community::ContentIdempotency.claim(
            user: @user,
            operation: "post.create",
            key: @idempotency_key,
            payload: idempotency_payload
          )
          raise ActiveRecord::Rollback if request_result.failure?

          if request_result.value[:replay]
            post = request_result.value[:resource]
            replayed = true
            next
          end

          spam_result = check_spam
          raise ActiveRecord::Rollback if spam_result.failure?

          attachment_result = Community::PreparePostAttachments.call(
            user: @user,
            attachment_ids: @attachment_ids
          )
          raise ActiveRecord::Rollback if attachment_result.failure?

          # Soft-deleted rows still participate in the database uniqueness
          # constraint, so their floor numbers must never be reused.
          floor_number = @topic.posts.with_discarded.maximum(:floor_number).to_i + 1

          post = Community::Post.create!(
            topic: @topic,
            user: @user,
            floor_number: floor_number,
            body: @body,
            quoted_post: @quoted_post,
            parent_post: @parent_post,
            status: post_status,
            post_type: @whisper ? "whisper" : "regular"
          )
          inline_upload_result = Community::BindInlineUploads.call(
            user: @user,
            post: post,
            body: @body
          )
          raise ActiveRecord::Rollback if inline_upload_result.failure?

          attachment_result = Community::LinkPostAttachments.call(
            user: @user,
            post: post,
            attachment_ids: @attachment_ids
          )
          raise ActiveRecord::Rollback if attachment_result.failure?

          Community::ReadState.mark_read!(@user, @topic, floor: post.floor_number)
          Community::Subscription.subscribe!(@user, @topic)
          request_result.value[:request]&.complete!(post)
        end
      rescue Community::SectionHierarchyLock::TopicSectionChanged,
        Community::SectionHierarchyLock::HierarchyChanged,
        ActiveRecord::Deadlocked
        section_lock_attempts += 1
        fresh_topic = Community::Topic.with_discarded.find_by(id: @topic.id)
        if section_lock_attempts <= 2 && fresh_topic
          @topic = fresh_topic
          retry
        end
        state_result = ServiceResult.failure(error: :topic_not_available)
      end

      return request_result if request_result&.failure?
      return spam_result if spam_result&.failure?
      return state_result if state_result&.failure?
      return attachment_result if attachment_result&.failure?
      return inline_upload_result if inline_upload_result&.failure?
      return ServiceResult.success(post) if replayed

      Administration::AuditLogger.call(
        actor: @user,
        action: "community.post_created",
        resource: post,
        ip_address: @ip_address
      )

      if needs_approval
        Community::NotifyPendingPost.call(post: post)
      elsif !@whisper
        Community::PublishPostSideEffects.call(post: post)
        award_post_points(post)
      end
      Community::CheckAutoBadges.call(user: @user)
      notify_trust_level_up!(old_trust_level)

      ServiceResult.success(post)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def reply_access_result
      unless Community::ForumAccess.topic_visible?(topic: @topic, user: @user)
        return ServiceResult.failure(error: :topic_not_available)
      end

      state_error = topic_reply_state_error
      return ServiceResult.failure(error: state_error) if state_error

      if @whisper && !can_post_whisper?
        return ServiceResult.failure(error: :you_are_not_allowed_to_post_staff_whispers)
      end

      unless @topic.section.allowed?(@user, :reply)
        return ServiceResult.failure(error: :you_are_not_allowed_to_reply_in_this_section)
      end

      unless @topic.section.trust_allowed?(@user, :reply)
        return ServiceResult.failure(error: :your_trust_level_is_too_low_to_reply_in_this_section)
      end

      unless @topic.section.writable_by?(@user, :reply)
        return ServiceResult.failure(error: :section_read_only)
      end

      if Community::TopicReplyBan.active.exists?(forum_topic_id: @topic.id, user_id: @user.id)
        return ServiceResult.failure(error: I18n.t("mcweb.services.errors.topic_reply_banned"))
      end

      if @parent_post && @parent_post.forum_topic_id != @topic.id
        return ServiceResult.failure(error: :invalid_parent_post)
      end

      if @quoted_post && !PostAccess.readable?(post: @quoted_post, user: @user)
        return ServiceResult.failure(error: :quoted_post_is_not_available)
      end

      if @parent_post && !PostAccess.readable?(post: @parent_post, user: @user)
        return ServiceResult.failure(error: :parent_post_is_not_available)
      end

      ServiceResult.success
    end

    def plugin_service_decorators_available?
      defined?(Mcweb::Plugins) && Mcweb::Plugins.respond_to?(:call_service)
    end

    def plugin_attributes
      {
        body: @body,
        whisper: @whisper
      }
    end

    def apply_plugin_attributes!(filtered)
      return unless filtered.is_a?(Hash)

      @body = filtered.fetch("body", @body).to_s.strip
      @whisper = ActiveModel::Type::Boolean.new.cast(
        filtered.fetch("whisper", @whisper)
      )
    end

    def topic_reply_state_error
      return "This topic is archived." if @topic.archived_at.present?
      return "This topic is not open for replies." unless @topic.status == "published"

      "This topic is locked." if @topic.locked?
    end

    def idempotency_payload
      {
        topic_id: @topic.id,
        body: @body,
        quoted_post_id: @quoted_post&.id,
        parent_post_id: @parent_post&.id,
        whisper: @whisper,
        attachment_ids: Array(@attachment_ids).map(&:to_s)
      }
    end

    # Reward the author for a newly published post. Side effect: never let an
    # awarding error bubble up and break post creation.
    def award_post_points(post)
      Community::AwardPoints.for_rule(user: post.user, rule: "post_created", source: post, default: 5)
    rescue StandardError => e
      Rails.logger.error("[AwardPoints] post_created failed for post=#{post.id}: #{e.class}: #{e.message}")
    end

    def check_spam
      if @body.length < MIN_BODY_LENGTH
        return ServiceResult.failure(error: :post_body_too_short)
      end

      if muted_in_section?
        return ServiceResult.failure(error: :muted_in_section)
      end

      if @user.banned?
        return ServiceResult.failure(error: :account_banned)
      end

      if Community::UserSilence.silenced?(@user)
        return ServiceResult.failure(error: :silenced_cannot_post)
      end

      ip_result = Administration::CheckIpBan.call(ip_address: @ip_address)
      return ip_result if ip_result.failure?

      if !developer_mode_bypasses_spam_gates? && slow_mode_active?
        return ServiceResult.failure(error: :slow_mode_active)
      end

      recent = Community::Post.where(user: @user).order(created_at: :desc).first
      if !developer_mode_bypasses_spam_gates? &&
          !@skip_interval_check &&
          recent &&
          recent.created_at > MIN_INTERVAL.ago
        return ServiceResult.failure(error: :wait_before_posting)
      end

      if !developer_mode_bypasses_spam_gates? && duplicate_body?
        return ServiceResult.failure(error: :duplicate_post_detected)
      end

      if Community::TrustLevel.contains_link?(@body) && !Community::TrustLevel.can_post_links?(@user)
        return ServiceResult.failure(error: :new_members_cannot_post_links)
      end

      link_restriction = Community::CheckWarningRestrictions.call(user: @user, action: :link)
      return link_restriction if link_restriction.failure? && Community::TrustLevel.contains_link?(@body)

      post_restriction = Community::CheckWarningRestrictions.call(user: @user, action: :post)
      return post_restriction if post_restriction.failure?

      ServiceResult.success
    end

    def developer_mode_bypasses_spam_gates?
      Mcweb::DeveloperMode.allow?(:skip_anti_spam)
    end

    def enforce_rate_limit
      Administration::AbuseRateLimit.call(
        action: :reply,
        account: @user,
        ip_address: @ip_address
      )
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

    def apply_plugin_filters!
      return unless defined?(Mcweb::Plugins) && Mcweb::Plugins.respond_to?(:apply_filter)

      filtered = Mcweb::Plugins.apply_filter(
        "forum.post.create.attributes",
        plugin_attributes,
        context: { user: @user, topic: @topic }
      )
      apply_plugin_attributes!(filtered)
    rescue StandardError => e
      Rails.logger.error("[mcweb.plugins] forum.post.create.attributes host integration failed: #{e.class}: #{e.message}")
    end

    def notify_trust_level_up!(old_level)
      info = Community::TrustLevel.level_info(@user)
      return if info[:level] <= old_level

      Community::NotifyTrustLevelUp.call(user: @user, level: info[:level])
    end

    def can_post_whisper?
      return true if @user.permission?("forum.topics.lock")
      return true if Community::SectionModeration.can_moderate_topic?(user: @user, topic: @topic)

      false
    end
  end
end
