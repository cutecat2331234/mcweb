# frozen_string_literal: true

module Community
  class NotificationsController < ApplicationController
    before_action :require_login

    def index
      notifications = current_user.notifications.recent.limit(50)

      render inertia: "Community/Notifications/Index", props: {
        notifications: notifications.map { |n| serialize_notification(n) }
      }
    end

    def mark_read
      notification = current_user.notifications.find(params[:id])
      notification.mark_read!
      redirect_to forum_notifications_path, notice: "已标记为已读。"
    end

    def mark_all_read
      current_user.notifications.unread.update_all(read_at: Time.current)
      redirect_to forum_notifications_path, notice: "全部已标记为已读。"
    end

    private

    def serialize_notification(notification)
      {
        id: notification.id,
        title: notification.title,
        body: notification.body,
        notification_type: notification.notification_type,
        read: notification.read?,
        created_at: l(notification.created_at, format: :short),
        url: notification.metadata["path"] || notification.metadata["url"],
        mark_read_url: mark_read_forum_notification_path(notification)
      }
    end
  end
end
