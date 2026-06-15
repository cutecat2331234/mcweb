# frozen_string_literal: true

module Community
  class GroupDigestNotifications
    TYPE_LABELS = NotificationTypeLabels::FORUM

    def self.call(notifications)
      new(notifications).sections
    end

    def initialize(notifications)
      @notifications = Array(notifications)
    end

    def sections
      grouped = @notifications.group_by(&:notification_type)
      grouped.map do |type, items|
        {
          type: type,
          label: TYPE_LABELS[type] || type.to_s.humanize,
          notifications: items.sort_by(&:created_at).reverse
        }
      end.sort_by { |section| -section[:notifications].first.created_at.to_i }
    end
  end
end
