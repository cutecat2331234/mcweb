# frozen_string_literal: true

module Minecraft
  class NotifyStaff < ApplicationService
    STAFF_PERMISSION = "minecraft.servers.manage"

    def initialize(notification_type:, title:, body:, metadata: {})
      @notification_type = notification_type
      @title = title
      @body = body
      @metadata = metadata
    end

    def call
      notified = 0
      staff_users.find_each do |user|
        next unless NotificationPreference.enabled?(user, channel: "in_app", notification_type: @notification_type)

        Notification.notify!(
          user: user,
          notification_type: @notification_type,
          title: @title,
          body: @body,
          metadata: @metadata
        )
        notified += 1
      end

      ServiceResult.success(notified: notified)
    end

    def self.staff_users
      User.joins(roles: :permissions)
        .where(permissions: { key: STAFF_PERMISSION })
        .distinct
    end

    private

    def staff_users
      self.class.staff_users
    end
  end
end
