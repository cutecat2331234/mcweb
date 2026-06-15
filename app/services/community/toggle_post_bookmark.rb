# frozen_string_literal: true

module Community
  class TogglePostBookmark < ApplicationService
    def initialize(user:, post:)
      @user = user
      @post = post
    end

    def call
      return ServiceResult.failure(error: "Post not available.") unless PostAccess.readable?(post: @post, user: @user)

      bookmark = Community::Bookmark.find_by(user: @user, post: @post)
      if bookmark
        bookmark.destroy!
        ServiceResult.success(bookmarked: false)
      else
        Community::Bookmark.create!(user: @user, topic: @post.topic, post: @post)
        ServiceResult.success(bookmarked: true)
      end
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
