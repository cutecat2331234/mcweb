# frozen_string_literal: true

module Community
  class EditPost < ApplicationService
    EDIT_WINDOW = 15.minutes
    NOT_PROVIDED = Object.new.freeze

    def self.editable_by?(user, post)
      return false unless user
      if user.id != post.user_id
        return true if user.permission?("forum.posts.edit_others") || user.permission?("forum.topics.lock")
        return true if Community::SectionModeration.section_moderator?(user, post.topic.section)
        return true if post.topic.wiki?
        return true if post.wiki_post?
        return false
      end

      return true if post.topic.wiki?
      return true if post.wiki_post?

      window = Community::TrustLevel.edit_window_for(user)
      return true if window.nil?

      post.created_at > window.ago
    end

    def initialize(
      user:,
      post:,
      body:,
      expected_revision: nil,
      reason: nil,
      attachment_ids: NOT_PROVIDED
    )
      @user = user
      @post = post
      @body = body.to_s.strip
      @expected_revision = Integer(expected_revision, exception: false)
      @reason = reason.to_s.strip.presence
      @attachment_ids = attachment_ids
      apply_plugin_filters!
    end

    def call
      return call_core unless plugin_service_decorators_available?

      Mcweb::Plugins.call_service(
        "forum.post.edit",
        input: plugin_attributes,
        context: { user: @user, post: @post, topic: @post.topic }
      ) do |input, _context|
        apply_plugin_attributes!(input)
        call_core
      end
    end

    def call_core
      return failure("post_revision_required") unless @expected_revision&.positive?
      return failure(:post_body_too_short) if @body.length < CreatePost::MIN_BODY_LENGTH
      persist_edit
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def persist_edit
      result = nil
      old_body = nil
      final_body = nil
      silent = false
      attachments_changed = false

      Community::Post.transaction do
        Identity::PermissionMutationLock.acquire_shared!
        @user = User.find_by(id: @user&.id)
        unless @user
          result = failure(:you_cannot_edit_this_post)
          raise ActiveRecord::Rollback
        end

        @post = Community::Post.with_discarded.lock.find(@post.id)
        unless PostAccess.editable?(post: @post, user: @user)
          result = failure(:post_not_available)
          raise ActiveRecord::Rollback
        end
        unless can_edit?
          result = failure(:you_cannot_edit_this_post)
          raise ActiveRecord::Rollback
        end
        if @post.revision != @expected_revision
          result = failure("post_revision_conflict")
          raise ActiveRecord::Rollback
        end

        if Community::TrustLevel.contains_link?(@body) && !Community::TrustLevel.can_post_links?(@user)
          result = failure(:new_members_cannot_post_links)
          raise ActiveRecord::Rollback
        end
        link_restriction = Community::CheckWarningRestrictions.call(user: @user, action: :link)
        if link_restriction.failure? && Community::TrustLevel.contains_link?(@body)
          result = link_restriction
          raise ActiveRecord::Rollback
        end
        filter_censored_body!

        old_body = @post.body
        silent = grace_edit?
        next_revision = @post.revision + 1
        edit = nil
        unless silent
          edit = @post.edits.create!(
            editor: @user,
            body_before: old_body,
            body_after: @body,
            reason: @reason
          )
        end
        @post.update!(
          body: @body,
          edited_at: (silent ? @post.edited_at : Time.current),
          revision: next_revision
        )

        inline_upload_result = Community::BindInlineUploads.call(
          user: @user,
          post: @post,
          body: @body
        )
        if inline_upload_result.failure?
          result = inline_upload_result
          raise ActiveRecord::Rollback
        end

        if @attachment_ids != NOT_PROVIDED
          sync_result = Community::SyncPostAttachments.call(
            user: @user,
            post: @post,
            attachment_ids: @attachment_ids
          )
          if sync_result.failure?
            result = sync_result
            raise ActiveRecord::Rollback
          end
          attachments_changed = sync_result.value[:changed]
        end

        final_body = @post.reload.body
        edit&.update!(body_after: final_body)
        result = ServiceResult.success(@post)
      end
      return result if result.failure?

      dispatch_post_edit_side_effects(
        old_body: old_body,
        final_body: final_body,
        silent: silent,
        attachments_changed: attachments_changed
      )
      result
    end

    def dispatch_post_edit_side_effects(old_body:, final_body:, silent:, attachments_changed:)
      Community::ProcessNewMentions.call(
        old_body: old_body,
        new_body: final_body,
        author: @user,
        post: @post,
        topic: @post.topic
      )
      Community::ProcessHashtags.call(topic: @post.topic, body: final_body, user: @user)
      body_changed = old_body != final_body
      Community::NotifyPostEdited.call(post: @post) if body_changed && !silent
      if (body_changed || attachments_changed) && !@post.whisper? && !silent
        Community::DispatchForumEventWebhook.call(event_type: "post.edited", topic: @post.topic, post: @post)
      end
    end

    def plugin_service_decorators_available?
      defined?(Mcweb::Plugins) && Mcweb::Plugins.respond_to?(:call_service)
    end

    def plugin_attributes
      {
        body: @body,
        reason: @reason
      }
    end

    def apply_plugin_attributes!(filtered)
      return unless filtered.is_a?(Hash)

      @body = filtered.fetch("body", @body).to_s.strip
      @reason = filtered.fetch("reason", @reason).to_s.strip.presence
    end

    def can_edit?
      self.class.editable_by?(@user, @post)
    end

    # Author editing their own brand-new post, before it has any tracked edit.
    def grace_edit?
      return false unless @user.id == @post.user_id

      minutes = SiteSetting.get("forum.edit_grace_period_minutes", "5").to_i
      return false if minutes <= 0

      @post.edited_at.nil? && @post.created_at > minutes.minutes.ago
    end

    def filter_censored_body!
      result = Community::FilterCensoredWords.call(text: @body)
      @body = result.value if result.success?
    end

    def apply_plugin_filters!
      return unless defined?(Mcweb::Plugins) && Mcweb::Plugins.respond_to?(:apply_filter)

      filtered = Mcweb::Plugins.apply_filter(
        "forum.post.edit.attributes",
        plugin_attributes,
        context: { user: @user, post: @post, topic: @post.topic }
      )
      apply_plugin_attributes!(filtered)
    rescue StandardError => e
      Rails.logger.error("[mcweb.plugins] forum.post.edit.attributes host integration failed: #{e.class}: #{e.message}")
    end

    def failure(code)
      ServiceResult.failure(error: code, code: code.to_s)
    end
  end
end
