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

      result = nil
      body = nil
      old_body = nil
      Community::Post.transaction do
        @user = User.lock.find_by(id: @user&.id)
        unless @user
          result = ServiceResult.failure(error: :not_allowed)
          raise ActiveRecord::Rollback
        end
        if @user.deleted? || @user.banned?
          result = ServiceResult.failure(
            error: @user.deleted? ? :account_deleted : :account_banned
          )
          raise ActiveRecord::Rollback
        end

        @post = Community::Post.with_discarded.lock.find_by(id: @post.id)
        @edit = Community::PostEdit.lock.find_by(id: @edit.id, forum_post_id: @post&.id)
        unless @post && @edit && PostAccess.editable?(post: @post, user: @user)
          result = ServiceResult.failure(error: :post_not_available)
          raise ActiveRecord::Rollback
        end
        unless can_restore?
          result = ServiceResult.failure(error: :not_allowed)
          raise ActiveRecord::Rollback
        end

        body = @edit.body_before.to_s
        if body.blank?
          result = ServiceResult.failure(error: :nothing_to_restore)
          raise ActiveRecord::Rollback
        end

        old_body = @post.body
        reason = I18n.t(
          "mcweb.forum.restore_post_edit.reason",
          time: I18n.l(@edit.created_at, format: :short)
        )
        filter = Community::FilterCensoredWords.call(text: body)
        body = filter.value if filter.success?
        @post.edit_body!(body, editor: @user, reason: reason)
        result = ServiceResult.success(@post)
      end
      return result if result.failure?

      Community::ProcessNewMentions.call(
        old_body: old_body,
        new_body: body,
        author: @user,
        post: @post,
        topic: @post.topic
      )
      result
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
