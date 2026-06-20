# frozen_string_literal: true

module Community
  class NotifyBookmarkReminder < ApplicationService
    def initialize(bookmark:)
      @bookmark = bookmark
      @user = bookmark.user
    end

    def call
      topic = @bookmark.topic
      unless topic&.status == "published"
        @bookmark.update_column(:remind_at, nil)
        return ServiceResult.success(skipped: true)
      end

      email_enabled = NotificationPreference.enabled?(@user, channel: "email", notification_type: "forum.bookmark_reminder")
      in_app_enabled = NotificationPreference.enabled?(@user, channel: "in_app", notification_type: "forum.bookmark_reminder")
      unless email_enabled || in_app_enabled
        @bookmark.update_column(:remind_at, nil)
        return ServiceResult.success(skipped: true)
      end

      path = if @bookmark.forum_post_id.present? && @bookmark.post
               "/app/forum/topics/#{topic.public_id}#post-#{@bookmark.post.id}"
      else
               "/app/forum/topics/#{topic.public_id}"
      end

      title = topic.title
      note = @bookmark.note.presence || Community::InAppNotification.t("bookmark_reminder.default_note")

      if in_app_enabled
        Community::InAppNotification.notify(
          user: @user,
          notification_type: "forum.bookmark_reminder",
          key: "bookmark_reminder",
          title: title,
          note: note.truncate(200),
          metadata: { path: path, bookmark_id: @bookmark.id }
        )
      end

      if email_enabled
        MailDeliveryJob.perform_later(
          "Community::ForumMailer",
          "bookmark_reminder",
          "deliver_now",
          args: [ @user.id, @bookmark.id ]
        )
      end

      @bookmark.update!(remind_at: nil)
      ServiceResult.success
    end
  end
end
