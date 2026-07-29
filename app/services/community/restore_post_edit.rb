# frozen_string_literal: true

module Community
  class RestorePostEdit < ApplicationService
    def initialize(user:, edit:)
      @user = user
      @edit = edit
      @post = edit.post
    end

    def call
      return ServiceResult.failure(error: :post_not_available) unless PostAccess.editable?(post: @post, user: @user)
      return ServiceResult.failure(error: :not_allowed) unless can_restore?

      body = @edit.body_before.to_s
      return ServiceResult.failure(error: :nothing_to_restore) if body.blank?

      old_body = @post.body
      reason = I18n.t("mcweb.forum.restore_post_edit.reason", time: I18n.l(@edit.created_at, format: :short))
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
      return true if @post.wiki_post?

      Community::SectionModeration.can_edit_post?(user: @user, post: @post)
    end
  end
end
