# frozen_string_literal: true

module Community
  class NotificationsController < ApplicationController
    before_action :require_login

    def index
      category = params[:category].to_s.presence
      notifications = current_user.notifications.recent.limit(100)
      notifications = filter_notifications_by_category(notifications, category)

      render inertia: "Community/Notifications/Index", props: {
        notifications: group_notifications(notifications),
        flat_notifications: notifications.limit(50).map { |n| serialize_notification(n) },
        activeCategory: category.presence || "all"
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
        category: notification_category(notification),
        read: notification.read?,
        created_at: l(notification.created_at, format: :short),
        url: notification.metadata["path"] || notification.metadata["url"],
        visit_url: visit_forum_notification_path(notification),
        mark_read_url: mark_read_forum_notification_path(notification)
      }
    end

    def notification_category(notification)
      notification.notification_type.to_s.start_with?("commerce.") ? "commerce" : "forum"
    end

    def filter_notifications_by_category(scope, category)
      case category
      when "forum"
        scope.where("notification_type NOT LIKE ?", "commerce.%")
      when "commerce"
        scope.where("notification_type LIKE ?", "commerce.%")
      else
        scope
      end
    end

    def group_notifications(notifications)
      grouped = notifications.group_by do |n|
        topic_id = n.metadata["topic_id"] || n.metadata.dig("topic", "id")
        conversation_id = n.metadata["conversation_id"]
        order_id = n.metadata["order_public_id"]

        if order_id.present?
          [ "commerce_order", order_id ]
        else
          group_key = topic_id || conversation_id || n.id
          [ n.notification_type, group_key ]
        end
      end

      grouped.map do |(type, group_key), items|
        latest = items.max_by(&:created_at)
        unread = items.count { |i| !i.read? }
        {
          key: "#{type}-#{group_key}",
          notification_type: type == "commerce_order" ? latest.notification_type : type,
          category: notification_category(latest),
          title: type == "commerce_order" ? "订单 #{group_key.to_s.sub(/\Aord_/, '').truncate(8)}" : latest.title,
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
