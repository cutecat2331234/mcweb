# frozen_string_literal: true

module Account
  class NotificationsController < ApplicationController
    include PrivateNoStoreResponse

    uses_frontend_template :portal
    skip_feature_guard

    before_action :require_login

    def index
      read_filter = notification_read_filter
      category = notification_category_filter
      type_filter = notification_type_filter
      period_filter = notification_period_filter
      base_scope = current_user.notifications.recent
      filtered_scope = apply_notification_filters(
        base_scope,
        category: category,
        read: read_filter,
        type: type_filter,
        period: period_filter
      )
      @pagy, notifications = pagy(:offset, filtered_scope, limit: 50, page: notification_page_filter || 1)
      notification_access = Account::NotificationAccess.new(
        user: current_user,
        notifications: notifications
      )

      unread_count = current_user.notifications.unread.count
      type_counts, type_unread_counts = notification_type_counts(
        base_scope,
        category: category,
        read: read_filter,
        period: period_filter
      )

      grouped = group_notifications(notifications, notification_access: notification_access)

      # Build the full Inertia response from the PRE-dismissal state above so the
      # current view still shows transient alerts as unread (unread_count was read
      # from the DB at line ~23, and each notification's read state is captured
      # while serializing here).
      render inertia: "Account/Notifications/Index", props: {
        notificationGroups: grouped,
        notificationSections: Community::GroupNotificationsByReadState.call(grouped),
        activeCategory: category.presence || "all",
        activeRead: read_filter.presence || "all",
        activeType: type_filter.to_s,
        activePeriod: period_filter.to_s,
        typeTabs: notification_type_tabs(
          category: category,
          read: read_filter,
          period: period_filter,
          counts: type_counts,
          unread_counts: type_unread_counts
        ),
        quickFilters: notification_quick_filters(
          category: category,
          read: read_filter,
          type: type_filter,
          period: period_filter,
          counts: type_counts,
          unread_counts: type_unread_counts
        ),
        periodFilters: notification_period_filters(category: category, read: read_filter, type: type_filter, period: period_filter),
        activeFilters: notification_active_filters(category: category, read: read_filter, type: type_filter, period: period_filter),
        categoryFilters: notification_category_filters,
        unreadCount: unread_count,
        dismissAlertsUrl: dismiss_alerts_account_notifications_path(notification_index_query_params),
        pagination: pagy_props(@pagy)
      }
    end

    def destroy
      current_user.notifications.find(params[:id]).destroy!
      redirect_to account_notifications_path(notification_index_query_params(valid_page: true)),
        notice: t("mcweb.flash.notification_deleted")
    end

    def visit
      notification = current_user.notifications.find(params[:id])
      notification.mark_read!
      unless notification_content_visible?(notification)
        redirect_to account_notifications_path(notification_index_query_params), alert: t("mcweb.flash.notification_unavailable")
        return
      end
      destination = safe_notification_path(notification)
      redirect_to destination
    end

    def mark_read
      notification = current_user.notifications.find(params[:id])
      notification.mark_read!
      redirect_to account_notifications_path(notification_index_query_params), notice: t("mcweb.flash.marked_read")
    end

    def mark_all_read
      unless notification_filter_constraints_valid?
        redirect_to account_notifications_path(notification_index_query_params),
          alert: t("mcweb.flash.notification_filters_invalid")
        return
      end

      category = notification_category_filter
      read_filter = notification_read_filter
      type_filter = notification_type_filter
      period_filter = notification_period_filter
      scope = current_user.notifications.unread
      scope = apply_notification_filters(scope, category: category, read: read_filter, type: type_filter, period: period_filter)
      scope.update_all(read_at: Time.current)
      redirect_to account_notifications_path(notification_index_query_params), notice: t("mcweb.flash.marked_read")
    end

    def dismiss_alerts
      current_user.notifications.unread.alerts.update_all(read_at: Time.current)
      return head :no_content if request.xhr? || request.format.json?

      redirect_to account_notifications_path(notification_index_query_params), notice: t("mcweb.flash.alerts_dismissed")
    end

    private

    def notification_index_query_params(valid_page: false)
      query = {
        category: notification_category_filter,
        read: notification_read_filter,
        type: notification_type_filter,
        period: notification_period_filter,
        page: notification_page_filter
      }.compact
      return query unless valid_page && query[:page]

      requested_page = Integer(query[:page], exception: false)
      return query.except(:page) unless requested_page&.positive?

      remaining = apply_notification_filters(
        current_user.notifications.recent,
        category: query[:category],
        read: query[:read],
        type: query[:type],
        period: query[:period]
      ).count
      last_page = [ (remaining.fdiv(50)).ceil, 1 ].max
      corrected_page = [ requested_page, last_page ].min
      corrected_page > 1 ? query.merge(page: corrected_page) : query.except(:page)
    end

    def safe_notification_path(notification)
      safe_local_redirect_path(
        notification.destination_path,
        fallback: account_notifications_path
      )
    end

    def serialize_notification(notification, notification_access: nil)
      visible = notification_content_visible?(notification, notification_access: notification_access)
      {
        id: notification.id,
        title: visible ? notification.title : t("mcweb.account.notifications.content_unavailable"),
        body: visible ? notification.body : t("mcweb.account.notifications.content_unavailable_body"),
        notification_type: notification.notification_type,
        category: notification_category(notification),
        read: notification.read?,
        auto_dismiss: notification.auto_dismiss,
        created_at: l(notification.created_at, format: :short),
        url: visible ? safe_notification_path(notification) : nil,
        visit_url: visible ? visit_account_notification_path(notification) : nil,
        mark_read_url: mark_read_account_notification_path(notification),
        delete_url: account_notification_path(notification)
      }
    end

    def notification_content_visible?(notification, notification_access: nil)
      access = notification_access || Account::NotificationAccess.new(
        user: current_user,
        notifications: [ notification ]
      )
      access.visible?(notification)
    end

    def notification_category(notification)
      Account::NotificationCategory.for(notification.notification_type)
    end

    def apply_notification_filters(scope, category:, read:, type:, period: nil)
      scope = filter_notifications_by_category(scope, category) if category.present?
      scope = scope.unread if read == "unread"
      scope = scope.where(notification_type: type) if type.present?
      scope = apply_notification_period(scope, period) if period.present?
      scope
    end

    def apply_notification_period(scope, period)
      Community::NotificationPeriodScope.call(scope, period)
    end

    def filter_notifications_by_category(scope, category)
      Account::NotificationCategory.apply(scope, category)
    end

    def notification_type_counts(base_scope, category:, read:, period: nil)
      scope = apply_notification_filters(base_scope.unscope(:order), category: category, read: read, type: nil, period: period)
      counts = scope.group(:notification_type).count
      unread_counts = read == "unread" ? counts : scope.unread.group(:notification_type).count
      [ counts, unread_counts ]
    end

    def notification_type_tabs(category:, read:, counts:, unread_counts:, period: nil)
      current = notification_type_filter.to_s

      tabs = counts.map do |type, count|
        unread = unread_counts[type].to_i
        {
          type: type,
          label: Community::NotificationTypeLabels.label_for(type),
          href: account_notifications_path(notification_tab_params(category: category, read: read, type: type, period: period)),
          active: current == type,
          count: count,
          unread_count: unread
        }
      end.sort_by { |tab| [ -tab[:unread_count], -tab[:count], tab[:label] ] }

      if current.present? && tabs.none? { |tab| tab[:type] == current }
        tabs.unshift({
          type: current,
          label: Community::NotificationTypeLabels.label_for(current),
          href: account_notifications_path(notification_tab_params(category: category, read: read, type: current, period: period)),
          active: true,
          count: 0,
          unread_count: 0
        })
      end

      tabs.first(12)
    end

    def notification_quick_filters(category:, read:, type:, period: nil, counts: nil, unread_counts: nil)
      Community::NotificationQuickFilters.call(
        user: current_user,
        category: category,
        read: read,
        active_type: type,
        period: period,
        counts: counts,
        unread_counts: unread_counts
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
      Community::NotificationActiveFilters.call(category: category.presence || "all", read: read, type: type, period: period)
    end

    def notification_category_filters
      Account::NotificationCategory.categories.map do |category|
        { key: category, label: Account::NotificationCategory.label(category) }
      end
    end

    def group_notifications(notifications, notification_access: nil)
      grouped = notifications.group_by do |n|
        metadata = notification_metadata(n)
        nested_topic = metadata["topic"] || metadata[:topic]
        nested_topic_id = if nested_topic.is_a?(Hash)
          nested_topic["id"] || nested_topic[:id]
        end
        topic_id = metadata["topic_id"] || metadata[:topic_id] || nested_topic_id
        conversation_id = metadata["conversation_id"] || metadata[:conversation_id]
        order_id = metadata["order_public_id"] || metadata[:order_public_id]

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
          title: type == "commerce_order" ? t("mcweb.account.notifications.order_title", number: group_key.to_s.sub(/\Aord_/, "").truncate(8)) : (notification_content_visible?(latest, notification_access: notification_access) ? latest.title : t("mcweb.account.notifications.content_unavailable")),
          body: items.size > 1 ? t("mcweb.account.notifications.grouped_body", count: items.size) : (notification_content_visible?(latest, notification_access: notification_access) ? latest.body : t("mcweb.account.notifications.content_unavailable_body")),
          count: items.size,
          unread_count: unread,
          read: unread.zero?,
          latest_at: l(latest.created_at, format: :short),
          latest_at_ts: latest.created_at.to_i,
          visit_url: notification_content_visible?(latest, notification_access: notification_access) && latest.destination_path.present? ? visit_account_notification_path(latest) : nil,
          delete_url: items.one? ? account_notification_path(latest) : nil,
          items: items.map { |n| serialize_notification(n, notification_access: notification_access) }
        }
      end.sort_by { |g| -g[:latest_at_ts] }
    end

    def notification_metadata(notification)
      values = notification.metadata
      values.is_a?(Hash) ? values : {}
    end

    def notification_filter_constraints_valid?
      category_valid = !params.key?(:category) || params[:category].blank? ||
        params[:category].to_s == "all" || notification_category_filter.present?
      read_valid = !params.key?(:read) || params[:read].blank? ||
        params[:read].to_s.in?(%w[all unread])
      type_valid = !params.key?(:type) || params[:type].blank? ||
        notification_type_filter.present?
      period_valid = !params.key?(:period) || params[:period].blank? ||
        notification_period_filter.present?

      category_valid && read_valid && type_valid && period_valid
    end

    def notification_category_filter
      Account::NotificationCategory.normalize(params[:category])
    end

    def notification_read_filter
      "unread" if params[:read].to_s == "unread"
    end

    def notification_type_filter
      value = params[:type].to_s
      value if value.match?(/\A[a-z0-9][a-z0-9_.:-]{0,119}\z/i)
    end

    def notification_period_filter
      value = params[:period].to_s
      value if Community::NotificationPeriodFilters::PERIODS.include?(value)
    end

    def notification_page_filter
      value = Integer(params[:page], exception: false)
      value if value&.positive?
    end
  end
end
