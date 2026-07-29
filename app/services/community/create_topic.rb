# frozen_string_literal: true

module Community
  class CreateTopic < ApplicationService
    MIN_INTERVAL = 30.seconds
    MIN_BODY_LENGTH = 2

    def initialize(user:, section:, title:, body:, tag_names: nil, ip_address: nil, poll_question: nil, poll_options: nil, poll_closes_days: nil, poll_multiple_choice: nil, poll_max_choices: nil, poll_hide_results_until_vote: nil, poll_anonymous: nil, prefix: nil, attachment_ids: nil, custom_fields: nil, idempotency_key: nil)
      @user = user
      @section = section
      @title = title.to_s.strip
      @body = body.to_s.strip
      @tag_names = tag_names
      @ip_address = ip_address
      @poll_question = poll_question.to_s.strip.presence
      @poll_options = Array(poll_options).map(&:to_s).map(&:strip).reject(&:blank?)
      @poll_closes_days = poll_closes_days.to_i
      @poll_multiple_choice = ActiveModel::Type::Boolean.new.cast(poll_multiple_choice) || false
      @poll_max_choices = [ poll_max_choices.to_i, 1 ].max
      @poll_hide_results_until_vote = ActiveModel::Type::Boolean.new.cast(poll_hide_results_until_vote) || false
      @poll_anonymous = ActiveModel::Type::Boolean.new.cast(poll_anonymous) || false
      @prefix = prefix.to_s.strip.presence
      @attachment_ids = attachment_ids
      @custom_fields = normalize_custom_fields(custom_fields)
      @idempotency_key = idempotency_key
      apply_plugin_filters!
      filter_censored_body!
    end

    def call
      return call_core unless plugin_service_decorators_available?

      Mcweb::Plugins.call_service(
        "forum.topic.create",
        input: plugin_attributes,
        context: { user: @user, section: @section }
      ) do |input, _context|
        apply_plugin_attributes!(input)
        call_core
      end
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    def call_core
      unless Community::SectionAccess.view?(section: @section, user: @user)
        return ServiceResult.failure(error: :section_not_available)
      end

      unless @section.allowed?(@user, :create_topic)
        return ServiceResult.failure(error: :cannot_create_topic_in_section)
      end

      unless @section.trust_allowed?(@user, :create_topic)
        return ServiceResult.failure(error: :trust_level_too_low)
      end

      unless @section.writable_by?(@user, :create_topic)
        return ServiceResult.failure(error: :section_read_only)
      end

      rate_result = enforce_rate_limit
      return rate_result if rate_result.failure?

      topic = nil
      opening_post = nil
      tag_result = nil
      field_result = nil
      attachment_result = nil
      inline_upload_result = nil
      request_result = nil
      spam_result = nil
      replayed = false
      needs_approval = Community::RequiresPostApproval.required_for?(user: @user)
      topic_status = needs_approval ? "hidden" : "published"
      post_status = needs_approval ? "pending_approval" : "published"
      Community::Topic.transaction do
        request_result = Community::ContentIdempotency.claim(
          user: @user,
          operation: "topic.create",
          key: @idempotency_key,
          payload: idempotency_payload
        )
        raise ActiveRecord::Rollback if request_result.failure?

        if request_result.value[:replay]
          topic = request_result.value[:resource]
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

        topic = Community::Topic.create!(
          public_id: generate_public_id,
          section: @section,
          user: @user,
          title: @title,
          prefix: valid_prefix,
          status: topic_status,
          last_posted_at: Time.current,
          last_post_user: @user,
          replies_count: 0
        )

        opening_post = Community::Post.create!(
          topic: topic,
          user: @user,
          floor_number: 1,
          body: @body,
          status: post_status
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
        create_poll!(topic) if @poll_question && @poll_options.size >= 2
        field_result = Community::SyncTopicFieldValues.call(
          topic: topic,
          user: @user,
          values: @custom_fields,
          require_required: true
        )
        raise ActiveRecord::Rollback unless field_result.success?

        attachment_result = Community::LinkPostAttachments.call(
          user: @user,
          post: opening_post,
          attachment_ids: @attachment_ids
        )
        raise ActiveRecord::Rollback if attachment_result.failure?

        Community::Subscription.subscribe!(@user, topic)
        Community::ReadState.mark_read!(@user, topic, floor: 1)
        request_result.value[:request]&.complete!(topic)
      end

      return request_result if request_result&.failure?
      return spam_result if spam_result&.failure?
      return attachment_result if attachment_result&.failure?
      return inline_upload_result if inline_upload_result&.failure?
      return tag_result if tag_result&.failure?
      return field_result if field_result&.failure?
      return ServiceResult.success(topic) if replayed

      Administration::AuditLogger.call(
        actor: @user,
        action: "community.topic_created",
        resource: topic,
        ip_address: @ip_address
      )

      if needs_approval
        Community::NotifyPendingPost.call(post: opening_post)
      else
        Community::PublishPostSideEffects.call(post: opening_post) if opening_post
      end
      Community::CheckAutoBadges.call(user: @user)

      ServiceResult.success(topic)
    end

    private

    def plugin_service_decorators_available?
      defined?(Mcweb::Plugins) && Mcweb::Plugins.respond_to?(:call_service)
    end

    def plugin_attributes
      {
        title: @title,
        body: @body,
        tag_names: @tag_names,
        prefix: @prefix,
        custom_fields: @custom_fields
      }
    end

    def idempotency_payload
      {
        section_id: @section.id,
        title: @title,
        body: @body,
        tag_names: Array(@tag_names),
        prefix: @prefix,
        poll_question: @poll_question,
        poll_options: @poll_options,
        poll_closes_days: @poll_closes_days,
        poll_multiple_choice: @poll_multiple_choice,
        poll_max_choices: @poll_max_choices,
        poll_hide_results_until_vote: @poll_hide_results_until_vote,
        poll_anonymous: @poll_anonymous,
        attachment_ids: Array(@attachment_ids).map(&:to_s),
        custom_fields: @custom_fields
      }
    end

    def check_spam
      if @title.blank?
        return ServiceResult.failure(error: :title_required)
      end

      if @body.length < MIN_BODY_LENGTH
        return ServiceResult.failure(error: :post_body_too_short)
      end

      if muted_in_section?
        return ServiceResult.failure(error: :muted_in_section)
      end

      if @section.requires_tags_or_groups? && @tag_names.blank?
        return ServiceResult.failure(error: @section.tag_requirements_message)
      end

      if @section.prefix_required? && @prefix.blank?
        return ServiceResult.failure(error: "section_topic_prefix_required")
      end

      if @user.banned?
        return ServiceResult.failure(error: :account_banned)
      end

      if Community::UserSilence.silenced?(@user)
        return ServiceResult.failure(error: :silenced_cannot_post)
      end

      ip_result = Administration::CheckIpBan.call(ip_address: @ip_address)
      return ip_result if ip_result.failure?

      recent = Community::Topic.where(user: @user).order(created_at: :desc).first
      if !developer_mode_bypasses_spam_gates? &&
          recent &&
          recent.created_at > MIN_INTERVAL.ago
        return ServiceResult.failure(error: :wait_before_new_topic)
      end

      if !developer_mode_bypasses_spam_gates? && duplicate_title?
        return ServiceResult.failure(error: :similar_topic_recent)
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
        action: :topic,
        account: @user,
        ip_address: @ip_address
      )
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

    def valid_prefix
      return nil if @prefix.blank?

      allowed = @section.prefix_names
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
        hide_results_until_vote: @poll_hide_results_until_vote,
        anonymous: @poll_anonymous
      )
    end

    def filter_censored_body!
      result = Community::FilterCensoredWords.call(text: @body)
      @body = result.value if result.success?
    end

    def apply_plugin_filters!
      return unless defined?(Mcweb::Plugins) && Mcweb::Plugins.respond_to?(:apply_filter)

      filtered = Mcweb::Plugins.apply_filter(
        "forum.topic.create.attributes",
        plugin_attributes,
        context: { user: @user, section: @section }
      )

      apply_plugin_attributes!(filtered)
    rescue StandardError => e
      Rails.logger.error("[mcweb.plugins] forum.topic.create.attributes host integration failed: #{e.class}: #{e.message}")
    end

    def apply_plugin_attributes!(filtered)
      return unless filtered.is_a?(Hash)

      @title = filtered.fetch("title", @title).to_s.strip
      @body = filtered.fetch("body", @body).to_s.strip
      @tag_names = filtered["tag_names"] if filtered.key?("tag_names")
      @prefix = filtered.fetch("prefix", @prefix).to_s.strip.presence
      @custom_fields = filtered["custom_fields"] if filtered.key?("custom_fields")
    end

    def normalize_custom_fields(values)
      raw = values.respond_to?(:to_unsafe_h) ? values.to_unsafe_h : values
      raw.is_a?(Hash) ? raw.stringify_keys : {}
    end
  end
end
