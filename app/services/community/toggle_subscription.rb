# frozen_string_literal: true

module Community
  class ToggleSubscription < ApplicationService
    def initialize(user:, topic:)
      @user = user
      @topic = topic
    end

    def call
      existing = Community::Subscription.find_by(user: @user, subscribable: @topic)
      if existing.nil?
        Community::Subscription.subscribe!(@user, @topic, level: "watching")
        return ServiceResult.success(watching: true, notification_level: "watching")
      end

      next_level = SubscriptionLevelCycler.next_level(existing.notification_level)
      if next_level
        existing.update!(notification_level: next_level)
        ServiceResult.success(watching: true, notification_level: next_level)
      else
        existing.destroy!
        ServiceResult.success(watching: false, notification_level: nil)
      end
    end
  end
end
