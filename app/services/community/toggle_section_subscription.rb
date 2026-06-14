# frozen_string_literal: true

module Community
  class ToggleSectionSubscription < ApplicationService
    def initialize(user:, section:)
      @user = user
      @section = section
    end

    def call
      existing = Community::Subscription.find_by(user: @user, subscribable: @section)
      if existing.nil?
        level = @section.default_notification_level.presence_in(Community::Subscription::NOTIFICATION_LEVELS) || "watching"
        Community::Subscription.subscribe!(@user, @section, level: level)
        return ServiceResult.success(watching: true, notification_level: level)
      end

      case existing.notification_level
      when "watching"
        existing.update!(notification_level: "tracking")
        ServiceResult.success(watching: true, notification_level: "tracking")
      else
        existing.destroy!
        ServiceResult.success(watching: false, notification_level: nil)
      end
    end
  end
end
