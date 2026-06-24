# frozen_string_literal: true

module Community
  class EditPost < ApplicationService
    EDIT_WINDOW = 15.minutes

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

    NOT_PROVIDED = Object.new.freeze

    def initialize(user:, post:, body:, reason: nil, attachment_ids: NOT_PROVIDED)
      @user = user
      @post = post
      @body = body.to_s.strip
      @reason = reason.to_s.strip.presence
      @old_body = post.body
      @attachment_ids = attachment_ids
    end

    def call
      return ServiceResult.failure(error: "Post not available.") unless PostAccess.editable?(post: @post, user: @user)
      return ServiceResult.failure(error: "Post body is too short.") if @body.length < CreatePost::MIN_BODY_LENGTH
      return ServiceResult.failure(error: "You cannot edit this post.") unless can_edit?

      if Community::TrustLevel.contains_link?(@body) && !Community::TrustLevel.can_post_links?(@user)
        return ServiceResult.failure(error: "New members cannot post links. Participate more to unlock this.")
      end

      link_restriction = Community::CheckWarningRestrictions.call(user: @user, action: :link)
      return link_restriction if link_restriction.failure? && Community::TrustLevel.contains_link?(@body)

      filter_censored_body!
      # "Ninja edit" grace window: a quick self-edit right after posting updates the body
      # in place without creating a revision or an "edited" marker (XF/Discourse parity).
      silent = grace_edit?
      if silent
        @post.update!(body: @body)
      else
        @post.edit_body!(@body, editor: @user, reason: @reason)
      end

      attachments_changed = false
      if @attachment_ids != NOT_PROVIDED
        sync_result = Community::SyncPostAttachments.call(
          user: @user,
          post: @post,
          attachment_ids: @attachment_ids
        )
        return sync_result if sync_result.failure?

        attachments_changed = sync_result.value[:changed]
      end

      Community::ProcessNewMentions.call(
        old_body: @old_body,
        new_body: @body,
        author: @user,
        post: @post,
        topic: @post.topic
      )
      Community::ProcessHashtags.call(topic: @post.topic, body: @body, user: @user)
      body_changed = @old_body != @body
      Community::NotifyPostEdited.call(post: @post) if body_changed && !silent
      if (body_changed || attachments_changed) && !silent
        Community::DispatchForumEventWebhook.call(event_type: "post.edited", topic: @post.topic, post: @post)
      end
      ServiceResult.success(@post)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def can_edit?
      self.class.editable_by?(@user, @post)
    end

    # Author editing their own brand-new post, before it has any tracked revision.
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
  end
end
