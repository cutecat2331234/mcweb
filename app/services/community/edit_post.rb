# frozen_string_literal: true

module Community
  class EditPost < ApplicationService
    EDIT_WINDOW = 15.minutes

    def self.editable_by?(user, post)
      return false unless user
      return true if user.permission?("forum.topics.lock")
      return true if post.topic.wiki?
      return true if post.wiki_post?
      return false unless user.id == post.user_id

      window = Community::TrustLevel.edit_window_for(user)
      return true if window.nil?

      post.created_at > window.ago
    end

    def initialize(user:, post:, body:, reason: nil)
      @user = user
      @post = post
      @body = body.to_s.strip
      @reason = reason.to_s.strip.presence
      @old_body = post.body
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
      @post.edit_body!(@body, editor: @user, reason: @reason)
      Community::ProcessNewMentions.call(
        old_body: @old_body,
        new_body: @body,
        author: @user,
        post: @post,
        topic: @post.topic
      )
      Community::ProcessHashtags.call(topic: @post.topic, body: @body, user: @user)
      Community::NotifyPostEdited.call(post: @post) if @old_body != @body
      ServiceResult.success(@post)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def can_edit?
      self.class.editable_by?(@user, @post)
    end

    def filter_censored_body!
      result = Community::FilterCensoredWords.call(text: @body)
      @body = result.value if result.success?
    end
  end
end
