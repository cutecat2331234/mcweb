# frozen_string_literal: true

module Community
  class RestorePostEdit < ApplicationService
    def initialize(user:, edit:)
      @user = user
      @edit = edit
      @post = edit.post
    end

    def call
      return ServiceResult.failure(error: "Not allowed.") unless can_restore?

      body = @edit.body_before.to_s
      return ServiceResult.failure(error: "Nothing to restore.") if body.blank?

      old_body = @post.body
      reason = "恢复至 #{I18n.l(@edit.created_at, format: :short)} 的版本"
      filter = Community::FilterCensoredWords.call(text: body)
      body = filter.value if filter.success?

      @post.edit_body!(body, editor: @user, reason: reason)
      Community::ProcessNewMentions.call(
        old_body: old_body,
        new_body: body,
        author: @user,
        post: @post,
        topic: @post.topic
      )

      ServiceResult.success(@post)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def can_restore?
      return true if @post.topic.wiki?
      return true if @user.permission?("forum.topics.lock")
      return true if @user.id == @post.user_id

      false
    end
  end
end
