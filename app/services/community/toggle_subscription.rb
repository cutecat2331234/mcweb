# frozen_string_literal: true

module Community
  class ToggleSubscription < ApplicationService
    def initialize(user:, topic:)
      @user = user
      @topic = topic
    end

    def call
      existing = Community::Subscription.find_by(user: @user, subscribable: @topic)
      if existing
        existing.destroy!
        ServiceResult.success(watching: false)
      else
        Community::Subscription.subscribe!(@user, @topic)
        ServiceResult.success(watching: true)
      end
    end
  end
end
