# frozen_string_literal: true

module Community
  class EditPost < ApplicationService
    EDIT_WINDOW = 15.minutes

    def self.editable_by?(user, post)
      return false unless user
      return true if user.permission?("forum.topics.lock")
      return true if post.topic.wiki?
      return false unless user.id == post.user_id

      post.created_at > EDIT_WINDOW.ago
    end

    def initialize(user:, post:, body:, reason: nil)
      @user = user
      @post = post
      @body = body.to_s.strip
      @reason = reason.to_s.strip.presence
      @old_body = post.body
    end

    def call
      return ServiceResult.failure(error: "Post body is too short.") if @body.length < CreatePost::MIN_BODY_LENGTH
      return ServiceResult.failure(error: "You cannot edit this post.") unless can_edit?

      @post.edit_body!(@body, editor: @user, reason: @reason)
      Community::ProcessNewMentions.call(
        old_body: @old_body,
        new_body: @body,
        author: @user,
        post: @post,
        topic: @post.topic
      )
      ServiceResult.success(@post)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def can_edit?
      self.class.editable_by?(@user, @post)
    end
  end
end
