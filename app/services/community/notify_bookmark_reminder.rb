# frozen_string_literal: true

module Community
  class NotifyBookmarkReminder < ApplicationService
    def initialize(bookmark:)
      @bookmark = bookmark
      @user = bookmark.user
    end

    def call
      topic = @bookmark.topic
      return ServiceResult.success unless topic&.status == "published"
      return ServiceResult.success unless NotificationPreference.enabled?(@user, channel: "in_app", notification_type: "forum.bookmark_reminder")

      path = if @bookmark.forum_post_id.present? && @bookmark.post
               "/forum/topics/#{topic.public_id}#post-#{@bookmark.post.id}"
             else
               "/forum/topics/#{topic.public_id}"
             end

      title = topic.title
      body = @bookmark.note.presence || "你设置的书签提醒时间到了。"

      Notification.notify!(
        user: @user,
        notification_type: "forum.bookmark_reminder",
        title: "书签提醒：#{title}",
        body: body.truncate(200),
        metadata: { path: path, bookmark_id: @bookmark.id }
      )

      @bookmark.update!(remind_at: nil)
      ServiceResult.success
    end
  end
end
