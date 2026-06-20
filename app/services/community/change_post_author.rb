# frozen_string_literal: true

module Community
  class ChangePostAuthor < ApplicationService
    def initialize(user:, post:, new_username:)
      @user = user
      @post = post
      @new_username = new_username.to_s.strip
    end

    def call
      unless @user.permission?("forum.topics.lock")
        return ServiceResult.failure(error: "change_post_author_unauthorized")
      end

      new_author = User.find_by(username: @new_username)
      return ServiceResult.failure(error: "user_not_found") unless new_author

      old_author_id = @post.user_id
      topic = @post.topic

      @post.update!(user: new_author)

      if @post.floor_number == 1
        topic.update!(user: new_author)
      end

      Community::SyncTopicLastPost.call(topic: topic) if topic.last_post_user_id == old_author_id

      Administration::AuditLogger.call(
        actor: @user,
        action: "community.post_author_changed",
        resource: @post,
        metadata: { from_user_id: old_author_id, to_user_id: new_author.id }
      )

      ServiceResult.success(@post)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
