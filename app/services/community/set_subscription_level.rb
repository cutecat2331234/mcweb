# frozen_string_literal: true

module Community
  class SetSubscriptionLevel < ApplicationService
    def initialize(user:, subscribable:, level:)
      @user = user
      @subscribable = subscribable
      @level = level.to_s
    end

    def call
      if @level.blank? || @level == "off"
        Community::Subscription.unsubscribe!(@user, @subscribable)
        return ServiceResult.success(watching: false, notification_level: nil)
      end

      unless Community::Subscription::NOTIFICATION_LEVELS.include?(@level)
        return ServiceResult.failure(error: "无效的通知级别")
      end

      Community::Subscription.subscribe!(@user, @subscribable, level: @level)
      ServiceResult.success(watching: true, notification_level: @level)
    end
  end
end
