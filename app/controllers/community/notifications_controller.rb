# frozen_string_literal: true

module Community
  class NotificationsController < ApplicationController
    before_action :require_login

    def index
      notifications = current_user.notifications.recent.limit(100)

      render inertia: "Community/Notifications/Index", props: {
        notifications: group_notifications(notifications),
        flat_notifications: notifications.limit(50).map { |n| serialize_notification(n) }
      }
    end

    def visit
      notification = current_user.notifications.find(params[:id])
      notification.mark_read!
      destination = notification.metadata["path"] || notification.metadata["url"] || forum_notifications_path
      redirect_to destination
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
        visit_url: visit_forum_notification_path(notification),
        mark_read_url: mark_read_forum_notification_path(notification)
      }
    end

    def group_notifications(notifications)
      grouped = notifications.group_by do |n|
        topic_id = n.metadata["topic_id"] || n.metadata.dig("topic", "id")
        [ n.notification_type, topic_id ]
      end

      grouped.map do |(type, topic_id), items|
        latest = items.max_by(&:created_at)
        unread = items.count { |i| !i.read? }
        {
          key: "#{type}-#{topic_id}",
          notification_type: type,
          title: latest.title,
          body: items.size > 1 ? "共 #{items.size} 条相关通知" : latest.body,
          count: items.size,
          unread_count: unread,
          read: unread.zero?,
          latest_at: l(latest.created_at, format: :short),
          latest_at_ts: latest.created_at.to_i,
          visit_url: latest.metadata["path"].present? ? visit_forum_notification_path(latest) : nil,
          items: items.first(5).map { |n| serialize_notification(n) }
        }
      end.sort_by { |g| -g[:latest_at_ts] }.first(30)
    end
  end
end
