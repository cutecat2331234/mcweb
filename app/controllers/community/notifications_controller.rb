# frozen_string_literal: true

module Community
  class NotificationsController < ApplicationController
    before_action :require_login

    def index
      read_filter = params[:read].to_s.presence
      category = params[:category].to_s.presence
      type_filter = params[:type].to_s.presence
      period_filter = params[:period].to_s.presence
      base_scope = current_user.notifications.recent
      filtered_scope = apply_notification_filters(
        base_scope,
        category: category,
        read: read_filter,
        type: type_filter,
        period: period_filter
      )
      notifications = filtered_scope.limit(100)

      unread_count = current_user.notifications.unread.count

      grouped = group_notifications(notifications)

      render inertia: "Community/Notifications/Index", props: {
        notifications: grouped,
        notificationSections: Community::GroupNotificationsByReadState.call(grouped),
        flat_notifications: notifications.limit(50).map { |n| serialize_notification(n) },
        activeCategory: category.presence || "all",
        activeRead: read_filter.presence || "all",
        activeType: type_filter.to_s,
        activePeriod: period_filter.to_s,
        typeTabs: notification_type_tabs(base_scope, category: category, read: read_filter, period: period_filter),
        quickFilters: notification_quick_filters(category: category, read: read_filter, type: type_filter, period: period_filter),
        periodFilters: notification_period_filters(category: category, read: read_filter, type: type_filter, period: period_filter),
        activeFilters: notification_active_filters(category: category, read: read_filter, type: type_filter, period: period_filter),
        unreadCount: unread_count
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
      category = params[:category].to_s.presence
      read_filter = params[:read].to_s.presence
      type_filter = params[:type].to_s.presence
      period_filter = params[:period].to_s.presence
      scope = current_user.notifications.unread
      scope = apply_notification_filters(scope, category: category, read: read_filter, type: type_filter, period: period_filter)
      scope.update_all(read_at: Time.current)
      redirect_to forum_notifications_path(
        category: category,
        read: read_filter,
        type: type_filter,
        period: period_filter
      ), notice: "已标记为已读。"
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

    def apply_notification_filters(scope, category:, read:, type:, period: nil)
      scope = filter_notifications_by_category(scope, category) if category.present?
      scope = scope.unread if read == "unread"
      scope = scope.where(notification_type: type) if type.present?
      scope = apply_notification_period(scope, period) if period.present?
      scope
    end

    def apply_notification_period(scope, period)
      case period.to_s
      when "today"
        scope.where("created_at >= ?", Time.zone.now.beginning_of_day)
      when "this_week"
        scope.where("created_at >= ?", Time.zone.now.beginning_of_week)
      else
        scope
      end
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

    def notification_type_tabs(base_scope, category:, read:, period: nil)
      scope = apply_notification_filters(base_scope.unscope(:order), category: category, read: read, type: nil, period: period)
      counts = scope.group(:notification_type).count
      unread_counts = scope.unread.group(:notification_type).count
      current = params[:type].to_s

      tabs = counts.map do |type, count|
        unread = unread_counts[type].to_i
        {
          type: type,
          label: NotificationTypeLabels.label_for(type),
          href: forum_notifications_path(notification_tab_params(category: category, read: read, type: type, period: period)),
          active: current == type,
          count: count,
          unread_count: unread
        }
      end.sort_by { |tab| [ -tab[:unread_count], -tab[:count], tab[:label] ] }

      if current.present? && tabs.none? { |tab| tab[:type] == current }
        tabs.unshift({
          type: current,
          label: NotificationTypeLabels.label_for(current),
          href: forum_notifications_path(notification_tab_params(category: category, read: read, type: current, period: period)),
          active: true,
          count: scope.where(notification_type: current).count,
          unread_count: scope.unread.where(notification_type: current).count
        })
      end

      tabs.first(12)
    end

    def notification_quick_filters(category:, read:, type:, period: nil)
      Community::NotificationQuickFilters.call(
        user: current_user,
        category: category,
        read: read,
        active_type: type,
        period: period
      )
    end

    def notification_period_filters(category:, read:, type:, period: nil)
      Community::NotificationPeriodFilters.call(
        user: current_user,
        category: category,
        read: read,
        type: type,
        active_period: period
      )
    end

    def notification_tab_params(category:, read:, type:, period: nil)
      {
        category: category.presence,
        read: read == "unread" ? "unread" : nil,
        type: type.presence,
        period: period.presence
      }.compact
    end

    def notification_active_filters(category:, read:, type:, period: nil)
      NotificationActiveFilters.call(category: category.presence || "all", read: read, type: type, period: period)
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
