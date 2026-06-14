# frozen_string_literal: true

module Community
  class ToggleBookmark < ApplicationService
    def initialize(user:, topic:)
      @user = user
      @topic = topic
    end

    def call
      bookmarked = Community::Bookmark.toggle!(@user, @topic)
      ServiceResult.success(bookmarked: bookmarked)
    end
  end
end
